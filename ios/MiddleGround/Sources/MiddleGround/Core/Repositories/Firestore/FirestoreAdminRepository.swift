import FirebaseFirestore
import Foundation

/// Every query here is refused unless the caller's token carries `admin: true`
/// (see `firestore.rules`). Failures surface as permission errors, which the view model
/// translates into "this account may not have admin access".
actor FirestoreAdminRepository: AdminRepository {
    /// Computed, not stored: constructing this type must not require FirebaseApp.configure().
    private var db: Firestore { Firestore.firestore() }

    func overview() async throws -> AdminOverview {
        var overview = AdminOverview()

        let statuses = ["pending", "accepted", "declined", "negotiated", "rescheduled", "countered", "saved"]
        let categories = RequestCategory.allCases
        // Funnel, in order.
        let funnel = [
            ("Signed up", "signed_up"),
            ("Finished onboarding", "onboarding_completed"),
            ("Created a group", "relationship_created"),
            ("Paired", "invite_redeemed"),
            ("Created a request", "request_created"),
            ("Answered a request", "request_responded")
        ]

        // Aggregation queries count server-side without reading the documents themselves —
        // cheaper, and it means the totals need no access to anybody's content.
        let totals = [
            CountQuery(collection: "users"),
            CountQuery(collection: "relationships"),
            CountQuery(collection: "requests"),
            CountQuery(collection: "events", since: Date().addingTimeInterval(-86_400)),
            CountQuery(collection: "events", since: Date().addingTimeInterval(-604_800))
        ]
        let statusQueries = statuses.map { CountQuery(collection: "requests", field: "status", equals: $0) }
        let categoryQueries = categories.map {
            CountQuery(collection: "requests", field: "category", equals: $0.rawValue)
        }
        let funnelQueries = funnel.map { CountQuery(collection: "events", field: "type", equals: $0.1) }

        // Paired groups.
        //
        // "Paired" means `participantIDs.count > 1`, and Firestore cannot query on array
        // length — `isPaired` is a computed Swift property, not a stored field, so there is
        // no aggregation query for this without denormalising it on write.
        //
        // This used to read a single `.limit(to: 500)` page and count in memory, so past 500
        // groups `pairedCount` — and with it `activationRate`, the one number that says
        // whether the product works at all — was silently wrong with nothing in the UI to
        // say so. Now it pages, and when it hits the ceiling it reports the count as
        // approximate rather than lying.
        //
        // It pages, so it is the slowest thing here; start it before the counts rather than
        // after them.
        async let pairedResult = countPairedRelationships()
        let values = try await Self.runAll(totals + statusQueries + categoryQueries + funnelQueries)

        // Walk the results in the order the queries were assembled above.
        var cursor = 0
        func take(_ count: Int) -> [Int] {
            defer { cursor += count }
            return Array(values[cursor..<(cursor + count)])
        }

        let totalValues = take(totals.count)
        overview.userCount = totalValues[0]
        overview.relationshipCount = totalValues[1]
        overview.requestCount = totalValues[2]
        overview.eventsLast24h = totalValues[3]
        overview.eventsLast7d = totalValues[4]

        for (status, value) in zip(statuses, take(statusQueries.count)) where value > 0 {
            overview.requestsByStatus[status] = value
        }
        for (category, value) in zip(categories, take(categoryQueries.count)) where value > 0 {
            overview.requestsByCategory[category.displayName] = value
        }
        for (step, value) in zip(funnel, take(funnelQueries.count)) {
            overview.funnel.append(AdminOverview.FunnelStep(label: step.0, count: value))
        }

        (overview.pairedCount, overview.pairedCountIsExact) = try await pairedResult

        return overview
    }

    func allUsers(limit: Int) async throws -> [User] {
        let snapshot = try await db.collection("users").limit(to: limit).getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: UserDTO.self).toModel() }
    }

    func allRequests(limit: Int) async throws -> [Request] {
        let snapshot = try await db.collection("requests")
            .order(by: "updatedAt", descending: true)
            .limit(to: limit)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: RequestDTO.self).toModel() }
    }

    func requests(forUser userID: String, limit: Int) async throws -> [Request] {
        let snapshot = try await db.collection("requests")
            .whereField("allParticipantIDs", arrayContains: userID)
            .order(by: "updatedAt", descending: true)
            .limit(to: limit)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: RequestDTO.self).toModel() }
    }

    func relationships(forUser userID: String) async throws -> [Relationship] {
        let snapshot = try await db.collection("relationships")
            .whereField("participantIDs", arrayContains: userID)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: RelationshipDTO.self).toModel() }
    }

    /// One server-side aggregation, described by value rather than as a built `Query`.
    ///
    /// Describing them this way is what lets them run concurrently: `Query` is a reference into
    /// the Firestore SDK and is not something to hand across task boundaries, whereas this is
    /// plain data. Each task builds its own query and throws it away again.
    private struct CountQuery: Sendable {
        let collection: String
        var field: String?
        var equals: String?
        var since: Date?
    }

    nonisolated private static func run(_ spec: CountQuery) async throws -> Int {
        var query: Query = Firestore.firestore().collection(spec.collection)
        if let field = spec.field, let equals = spec.equals {
            query = query.whereField(field, isEqualTo: equals)
        }
        if let since = spec.since {
            query = query.whereField("at", isGreaterThan: Timestamp(date: since))
        }
        return try await query.count.getAggregation(source: .server).count.intValue
    }

    /// Runs every count at once and returns the results in the order they were given.
    ///
    /// The overview issued twenty-four of these one after another — three totals, two event
    /// windows, seven statuses, six categories and six funnel steps — each waiting a full
    /// network round trip before the next began. Nothing in that list depends on anything
    /// else in it, so the tab spent five to ten seconds blank for no reason.
    nonisolated private static func runAll(_ specs: [CountQuery]) async throws -> [Int] {
        try await withThrowingTaskGroup(of: (Int, Int).self) { group in
            for (index, spec) in specs.enumerated() {
                group.addTask { (index, try await run(spec)) }
            }
            var results = [Int](repeating: 0, count: specs.count)
            for try await (index, value) in group { results[index] = value }
            return results
        }
    }

    /// Pages through relationships counting the paired ones.
    ///
    /// Returns `(count, isExact)`. `isExact` is false once the ceiling is reached, so the UI
    /// can show "5000+" instead of a confidently wrong number. If this ever starts returning
    /// false in practice, that is the signal to denormalise a stored `isPaired` field on write
    /// and replace the whole thing with one aggregation query.
    private func countPairedRelationships(ceiling: Int = 5_000) async throws -> (Int, Bool) {
        var paired = 0
        var scanned = 0
        var cursor: DocumentSnapshot?

        while scanned < ceiling {
            var query = db.collection("relationships")
                .order(by: FieldPath.documentID())
                .limit(to: 500)
            if let cursor { query = query.start(afterDocument: cursor) }

            let page = try await query.getDocuments()
            if page.documents.isEmpty { return (paired, true) }

            paired += page.documents.filter {
                (($0.data()["participantIDs"] as? [String]) ?? []).count > 1
            }.count
            scanned += page.documents.count
            cursor = page.documents.last

            if page.documents.count < 500 { return (paired, true) }
        }
        return (paired, false)
    }
}

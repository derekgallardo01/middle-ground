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

        // Aggregation queries count server-side without reading the documents themselves —
        // cheaper, and it means the totals need no access to anybody's content.
        overview.userCount = try await count(of: db.collection("users"))
        overview.relationshipCount = try await count(of: db.collection("relationships"))
        overview.requestCount = try await count(of: db.collection("requests"))

        overview.eventsLast24h = try await count(
            of: db.collection("events")
                .whereField("at", isGreaterThan: Timestamp(date: Date().addingTimeInterval(-86_400)))
        )
        overview.eventsLast7d = try await count(
            of: db.collection("events")
                .whereField("at", isGreaterThan: Timestamp(date: Date().addingTimeInterval(-604_800)))
        )

        for status in ["pending", "accepted", "declined", "negotiated", "rescheduled", "countered", "saved"] {
            let value = try await count(of: db.collection("requests").whereField("status", isEqualTo: status))
            if value > 0 { overview.requestsByStatus[status] = value }
        }

        for category in RequestCategory.allCases {
            let value = try await count(
                of: db.collection("requests").whereField("category", isEqualTo: category.rawValue)
            )
            if value > 0 { overview.requestsByCategory[category.displayName] = value }
        }

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
        (overview.pairedCount, overview.pairedCountIsExact) = try await countPairedRelationships()

        // Funnel, in order. Each is a server-side count over the events collection, so the
        // whole section costs a handful of aggregation reads rather than a table scan.
        for (key, type) in [
            ("Signed up", "signed_up"),
            ("Finished onboarding", "onboarding_completed"),
            ("Created a group", "relationship_created"),
            ("Paired", "invite_redeemed"),
            ("Created a request", "request_created"),
            ("Answered a request", "request_responded")
        ] {
            let value = try await count(
                of: db.collection("events").whereField("type", isEqualTo: type)
            )
            overview.funnel.append(AdminOverview.FunnelStep(label: key, count: value))
        }

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

    private func count(of query: Query) async throws -> Int {
        try await query.count.getAggregation(source: .server).count.intValue
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

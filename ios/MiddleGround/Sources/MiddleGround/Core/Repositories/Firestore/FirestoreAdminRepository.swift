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

        // "Paired" needs the documents, since it is a property of the array's size.
        let relationships = try await db.collection("relationships").limit(to: 500).getDocuments()
        overview.pairedCount = relationships.documents.filter {
            (($0.data()["participantIDs"] as? [String]) ?? []).count > 1
        }.count

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
}

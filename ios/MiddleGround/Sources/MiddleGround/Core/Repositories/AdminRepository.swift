import Foundation

/// Cross-user reads for the admin panel.
///
/// Separated from the per-user repositories on purpose: these queries are meaningless — and
/// denied — for a normal account, so keeping them apart makes the privileged surface obvious in
/// the code rather than hidden inside a shared repository.
protocol AdminRepository: Sendable {
    func overview() async throws -> AdminOverview
    func allUsers(limit: Int) async throws -> [User]
    func allRequests(limit: Int) async throws -> [Request]
    func requests(forUser userID: String, limit: Int) async throws -> [Request]
    func relationships(forUser userID: String) async throws -> [Relationship]
}

actor MockAdminRepository: AdminRepository {
    func overview() async throws -> AdminOverview {
        AdminOverview(
            userCount: 2,
            relationshipCount: 1,
            pairedCount: 1,
            requestCount: 3,
            requestsByStatus: ["pending": 1, "accepted": 1, "negotiated": 1],
            requestsByCategory: ["relationship": 1, "travel": 1, "friends": 1],
            eventsLast24h: 12,
            eventsLast7d: 48
        )
    }

    func allUsers(limit: Int) async throws -> [User] { [.preview, .preview2] }

    func allRequests(limit: Int) async throws -> [Request] {
        [.preview, .previewNegotiating, .previewAccepted]
    }

    func requests(forUser userID: String, limit: Int) async throws -> [Request] {
        try await allRequests(limit: limit).filter { $0.allParticipantIDs.contains(userID) }
    }

    func relationships(forUser userID: String) async throws -> [Relationship] {
        [.preview].filter { $0.participantIDs.contains(userID) }
    }
}

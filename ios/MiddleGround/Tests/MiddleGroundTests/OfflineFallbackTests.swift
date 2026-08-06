import SwiftData
import XCTest
@testable import MiddleGround

/// What the app knows when the network is gone.
///
/// Every cached repository is written remote-first, which is right. Two of the three then let the
/// remote failure propagate, so the local copy — already on disk, already correct — was never
/// read. The worst consequence was the sign-in wall: `AuthService.currentUser()` wraps the user
/// read in `try?`, `AppState` turns nil into "not onboarded", and the app replaced itself with
/// onboarding for somebody whose account and session were both perfectly intact.
final class OfflineFallbackTests: XCTestCase {
    private var modelContainer: ModelContainer!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let schema = Schema([RequestEntity.self, UserEntity.self, RelationshipEntity.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [config])
    }

    override func tearDown() {
        modelContainer = nil
        super.tearDown()
    }

    /// A remote that works once and then loses the network, which is the sequence that matters:
    /// something has to reach the cache before the cache can save anybody.
    private actor UnreachableUserRepository: UserRepository {
        private var isReachable = true
        private let user: User

        init(user: User) { self.user = user }

        func goOffline() { isReachable = false }

        private func requireNetwork() throws {
            guard isReachable else {
                throw NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
            }
        }

        func currentUser() async throws -> User? {
            try requireNetwork()
            return user
        }

        func saveUser(_ user: User) async throws { try requireNetwork() }

        func user(id: String) async throws -> User? {
            try requireNetwork()
            return id == user.id ? user : nil
        }
    }

    private actor UnreachableRelationshipRepository: RelationshipRepository {
        private var isReachable = true
        private let relationships: [Relationship]

        init(relationships: [Relationship]) { self.relationships = relationships }

        func goOffline() { isReachable = false }

        private func requireNetwork() throws {
            guard isReachable else {
                throw NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
            }
        }

        func fetchRelationships(for userID: String) async throws -> [Relationship] {
            try requireNetwork()
            return relationships.filter { $0.participantIDs.contains(userID) }
        }

        func saveRelationship(_ relationship: Relationship) async throws { try requireNetwork() }
        func invite(forCode code: String) async throws -> RelationshipInvite? {
            try requireNetwork()
            return nil
        }
        func addParticipant(_ userID: String, to relationshipID: String) async throws { try requireNetwork() }
        func removeParticipant(_ userID: String, from relationshipID: String) async throws { try requireNetwork() }
        func rotateInviteCode(
            to newCode: String,
            from oldCode: String?,
            relationshipID: String,
            ownerID: String
        ) async throws {
            try requireNetwork()
        }
        func revokeInvite(code: String) async throws { try requireNetwork() }
    }

    // MARK: - The sign-in wall

    func testAKnownUserSurvivesLosingTheNetwork() async throws {
        let remote = UnreachableUserRepository(user: .preview)
        let repository = CachedUserRepository(remote: remote, modelContainer: modelContainer)

        // Online once, so the profile is cached the way a real session would have cached it.
        let online = try await repository.user(id: User.preview.id)
        XCTAssertEqual(online?.id, User.preview.id)

        await remote.goOffline()
        let offline = try await repository.user(id: User.preview.id)

        XCTAssertEqual(
            offline?.id,
            User.preview.id,
            "an offline read must not report that nobody is signed in"
        )
        XCTAssertEqual(offline?.name, "Alex")
    }

    func testCurrentUserAlsoFallsBackRatherThanThrowing() async throws {
        let remote = UnreachableUserRepository(user: .preview)
        let repository = CachedUserRepository(remote: remote, modelContainer: modelContainer)

        _ = try await repository.user(id: User.preview.id)
        await remote.goOffline()

        // Not asserting a value: `currentUser` caches under the remote's own id, so what matters
        // is that it answers instead of throwing — throwing is what became "please sign in".
        do {
            _ = try await repository.currentUser()
        } catch {
            XCTFail("an unreachable server must not propagate out of the cache layer: \(error)")
        }
    }

    /// Nobody has ever signed in on this device, so there is nothing cached and nil is honest.
    func testAnUnknownUserOfflineIsStillNil() async throws {
        let remote = UnreachableUserRepository(user: .preview)
        await remote.goOffline()
        let repository = CachedUserRepository(remote: remote, modelContainer: modelContainer)

        let result = try await repository.user(id: "never_seen")

        XCTAssertNil(result)
    }

    // MARK: - Who you are paired with

    func testRelationshipsSurviveLosingTheNetwork() async throws {
        let remote = UnreachableRelationshipRepository(relationships: [.preview, .previewGroup])
        let repository = CachedRelationshipRepository(remote: remote, modelContainer: modelContainer)

        let online = try await repository.fetchRelationships(for: User.preview.id)
        XCTAssertEqual(online.count, 2)

        await remote.goOffline()
        let offline = try await repository.fetchRelationships(for: User.preview.id)

        XCTAssertEqual(
            Set(offline.map(\.id)),
            Set(["rel_1", "rel_2"]),
            "partners are upstream of Create Request, the calendar and the profile"
        )
    }

    // MARK: - Writes that never landed

    /// `needsSync` is written in three places and read in none — there is no sync engine, and
    /// nothing anywhere replays a pending row. So a create that failed left a request in the local
    /// store that existed for nobody else, and the feed served it back on every load: a plan the
    /// recipient was never sent, waiting indefinitely for a reply that could not come.
    func testARequestThatNeverReachedTheServerDoesNotHauntTheFeed() async throws {
        let remote = UnwritableRequestRepository()
        let repository = CachedRequestRepository(remote: remote, modelContainer: modelContainer)
        let request = Request(creatorID: "u1", recipientIDs: ["u2"], category: .daily, title: "Dinner?")

        do {
            try await repository.createRequest(request)
            XCTFail("the remote refused the write; that has to reach the caller")
        } catch {
            // Expected — the view model turns this into a message.
        }

        let feed = try await repository.fetchRequests(for: "u1")
        XCTAssertFalse(
            feed.contains { $0.id == request.id },
            "a request nobody else has must not sit in the feed looking sent"
        )
    }

    /// An edit that failed leaves the request itself alone — it existed before and still does.
    func testAFailedEditLeavesTheOriginalIntact() async throws {
        let remote = UnwritableRequestRepository()
        let repository = CachedRequestRepository(remote: remote, modelContainer: modelContainer)
        var request = Request(creatorID: "u1", recipientIDs: ["u2"], category: .daily, title: "Original")

        await remote.allowWrites()
        try await repository.createRequest(request)
        await remote.refuseWrites()

        request.title = "Edited while offline"
        request.updatedAt = Date().addingTimeInterval(60)
        do {
            try await repository.updateRequest(request)
            XCTFail("the remote refused the write")
        } catch {
            // Expected.
        }

        let feed = try await repository.fetchRequests(for: "u1")
        let stored = try XCTUnwrap(feed.first { $0.id == request.id })
        XCTAssertEqual(stored.title, "Original", "the edit did not happen, so it must not appear to have")
    }
}

/// A remote that can refuse writes while reads keep working — the shape of a failed send.
actor UnwritableRequestRepository: RequestRepository {
    private var stored: [Request] = []
    private var writesAllowed = false

    func allowWrites() { writesAllowed = true }
    func refuseWrites() { writesAllowed = false }

    private func requireWritable() throws {
        guard writesAllowed else {
            throw NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        }
    }

    func fetchRequests(for userID: String) async throws -> [Request] { stored }

    func createRequest(_ request: Request) async throws {
        try requireWritable()
        stored.append(request)
    }

    func updateRequest(_ request: Request) async throws {
        try requireWritable()
        if let index = stored.firstIndex(where: { $0.id == request.id }) { stored[index] = request }
    }

    func appendMessage(
        _ message: NegotiationMessage,
        to requestID: String,
        proposedTime: Date?
    ) async throws -> Request {
        try requireWritable()
        throw NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
    }

    func deleteRequest(_ request: Request) async throws {
        try requireWritable()
        stored.removeAll { $0.id == request.id }
    }

    func publishPlanInvite(code: String, requestID: String, ownerID: String) async throws {
        try requireWritable()
    }

    func planInvite(forCode code: String) async throws -> String? { nil }

    func addParticipant(_ userID: String, to requestID: String) async throws { try requireWritable() }

    nonisolated func observeRequests(for userID: String) -> AsyncStream<[Request]> {
        AsyncStream { $0.finish() }
    }
}

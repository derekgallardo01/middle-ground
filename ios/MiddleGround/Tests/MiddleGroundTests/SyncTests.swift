import XCTest
import SwiftData
@testable import MiddleGround

final class SyncTests: XCTestCase {
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

    /// Assertions target the specific request rather than a total count, because the mock
    /// remote seeds its own fixtures and merging them in is correct behaviour.
    func testCachedRequestRepositoryStoresRequestLocally() async throws {
        let remote = MockRequestRepository()
        let repository = CachedRequestRepository(remote: remote, modelContainer: modelContainer)
        let request = Request(creatorID: "u1", recipientIDs: ["u2"], category: .daily, title: "Dinner?")

        try await repository.createRequest(request)
        let localRequests = try await repository.fetchRequests(for: "u1")

        let stored = try XCTUnwrap(localRequests.first { $0.id == request.id })
        XCTAssertEqual(stored.title, "Dinner?")
        XCTAssertEqual(stored.creatorID, "u1")
    }

    func testCachedRequestRepositoryMergesRemoteUpdates() async throws {
        let remote = MockRequestRepository()
        let repository = CachedRequestRepository(remote: remote, modelContainer: modelContainer)

        let request = Request(creatorID: "u1", recipientIDs: ["u2"], category: .daily, title: "Remote request")
        try await remote.createRequest(request)

        // fetchRequests must merge the remote before returning; it previously refreshed in a
        // detached Task and handed back a stale snapshot.
        let localRequests = try await repository.fetchRequests(for: "u1")

        let merged = try XCTUnwrap(localRequests.first { $0.id == request.id })
        XCTAssertEqual(merged.title, "Remote request")
    }

    func testRemoteUpdatesOverwriteOlderLocalCopies() async throws {
        let remote = MockRequestRepository()
        let repository = CachedRequestRepository(remote: remote, modelContainer: modelContainer)

        var request = Request(creatorID: "u1", recipientIDs: ["u2"], category: .daily, title: "Original")
        try await repository.createRequest(request)

        request.title = "Updated remotely"
        request.updatedAt = Date().addingTimeInterval(60)
        try await remote.updateRequest(request)

        let localRequests = try await repository.fetchRequests(for: "u1")
        let merged = try XCTUnwrap(localRequests.first { $0.id == request.id })
        XCTAssertEqual(merged.title, "Updated remotely", "newer remote copy wins")
    }

    func testObserveRequestsYieldsCachedData() async throws {
        let remote = MockRequestRepository()
        let repository = CachedRequestRepository(remote: remote, modelContainer: modelContainer)
        let request = Request(creatorID: "u1", recipientIDs: ["u2"], category: .daily, title: "Streamed")
        try await repository.createRequest(request)

        var received: [Request]?
        for await batch in repository.observeRequests(for: "u1") {
            received = batch
            break
        }

        let batch = try XCTUnwrap(received)
        XCTAssertTrue(batch.contains { $0.id == request.id })
    }
}

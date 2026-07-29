import XCTest
import SwiftData
@testable import MiddleGround

final class SyncTests: XCTestCase {
    private var modelContainer: ModelContainer!
    
    override func setUp() {
        super.setUp()
        let schema = Schema([RequestEntity.self, UserEntity.self, RelationshipEntity.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        modelContainer = try! ModelContainer(for: schema, configurations: [config])
    }
    
    func testCachedRequestRepositoryStoresRequestLocally() async throws {
        let remote = MockRequestRepository()
        let repository = CachedRequestRepository(remote: remote, modelContainer: modelContainer)
        let request = Request(creatorID: "u1", recipientIDs: ["u2"], category: .daily, title: "Dinner?")
        
        try await repository.createRequest(request)
        let localRequests = try await repository.fetchRequests(for: "u1")
        
        XCTAssertEqual(localRequests.count, 1)
        XCTAssertEqual(localRequests.first?.title, "Dinner?")
    }
    
    func testCachedRequestRepositoryMergesRemoteUpdates() async throws {
        let remote = MockRequestRepository()
        let repository = CachedRequestRepository(remote: remote, modelContainer: modelContainer)
        
        // Seed remote
        let request = Request(creatorID: "u1", recipientIDs: ["u2"], category: .daily, title: "Remote request")
        try await remote.createRequest(request)
        
        // Fetch should merge remote into local
        let localRequests = try await repository.fetchRequests(for: "u1")
        
        XCTAssertEqual(localRequests.count, 1)
        XCTAssertEqual(localRequests.first?.title, "Remote request")
    }
}

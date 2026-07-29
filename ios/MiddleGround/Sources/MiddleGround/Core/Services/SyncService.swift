import Foundation

/// Coordinates local cache and remote sync.
/// The cached repositories handle persistence; this service provides a clean facade for view models.
actor SyncService {
    private let requestRepository: RequestRepository
    private let userRepository: UserRepository
    private let relationshipRepository: RelationshipRepository
    
    init(
        requestRepository: RequestRepository,
        userRepository: UserRepository,
        relationshipRepository: RelationshipRepository
    ) {
        self.requestRepository = requestRepository
        self.userRepository = userRepository
        self.relationshipRepository = relationshipRepository
    }
    
    func syncRequests(for userID: String) async throws -> [Request] {
        try await requestRepository.fetchRequests(for: userID)
    }
    
    func observeRequests(for userID: String) -> AsyncStream<[Request]> {
        requestRepository.observeRequests(for: userID)
    }
    
    func createRequest(_ request: Request) async throws {
        try await requestRepository.createRequest(request)
    }
    
    func updateRequest(_ request: Request) async throws {
        try await requestRepository.updateRequest(request)
    }
    
    func currentUser() async throws -> User? {
        try await userRepository.currentUser()
    }
    
    func saveUser(_ user: User) async throws {
        try await userRepository.saveUser(user)
    }
    
    func relationships(for userID: String) async throws -> [Relationship] {
        try await relationshipRepository.fetchRelationships(for: userID)
    }
}

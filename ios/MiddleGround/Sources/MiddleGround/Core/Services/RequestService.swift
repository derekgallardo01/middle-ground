import Foundation

@Observable
final class RequestService {
    private let repository: RequestRepository
    
    init(repository: RequestRepository) {
        self.repository = repository
    }
    
    func fetchRequests(for userID: String) async throws -> [Request] {
        try await repository.fetchRequests(for: userID)
    }
    
    func observeRequests(for userID: String) -> AsyncStream<[Request]> {
        repository.observeRequests(for: userID)
    }
    
    func createRequest(_ request: Request) async throws {
        try await repository.createRequest(request)
    }
    
    func respond(to request: Request, with response: ResponseType, text: String? = nil, by userID: String) async throws -> Request {
        var updated = request
        let message = NegotiationMessage(
            senderID: userID,
            responseType: response,
            text: text
        )
        updated.addResponse(message)
        try await repository.updateRequest(updated)
        return updated
    }
}

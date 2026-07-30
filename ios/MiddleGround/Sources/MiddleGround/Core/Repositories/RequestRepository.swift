import Foundation

protocol RequestRepository: Sendable {
    func fetchRequests(for userID: String) async throws -> [Request]
    func createRequest(_ request: Request) async throws
    func updateRequest(_ request: Request) async throws
    func deleteRequest(_ request: Request) async throws
    func observeRequests(for userID: String) -> AsyncStream<[Request]>
}

actor MockRequestRepository: RequestRepository {
    private var requests: [Request] = [.preview, .previewNegotiating, .previewAccepted]

    func fetchRequests(for userID: String) async throws -> [Request] {
        try await Task.sleep(nanoseconds: 300_000_000)
        return requests
    }

    func createRequest(_ request: Request) async throws {
        requests.insert(request, at: 0)
    }

    func updateRequest(_ request: Request) async throws {
        if let index = requests.firstIndex(where: { $0.id == request.id }) {
            requests[index] = request
        }
    }

    func deleteRequest(_ request: Request) async throws {
        requests.removeAll { $0.id == request.id }
    }

    nonisolated func observeRequests(for userID: String) -> AsyncStream<[Request]> {
        AsyncStream { continuation in
            Task {
                continuation.yield(await self.requests)
                continuation.finish()
            }
        }
    }
}

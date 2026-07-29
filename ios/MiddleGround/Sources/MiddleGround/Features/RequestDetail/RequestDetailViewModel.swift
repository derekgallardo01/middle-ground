import Foundation
import Factory

@MainActor
@Observable
final class RequestDetailViewModel {
    private let requestService = Container.shared.requestService()
    private let authService = Container.shared.authService()
    
    var request: Request
    var currentUser: User?
    var counterText: String = ""
    var isSending = false
    var errorMessage: String?
    
    init(request: Request) {
        self.request = request
        Task { await loadCurrentUser() }
    }
    
    func loadCurrentUser() async {
        currentUser = await authService.currentUser()
    }
    
    var isCounterEmpty: Bool {
        counterText.trimmingCharacters(in: .whitespaces).isEmpty
    }
    
    func respond(with response: ResponseType, text: String? = nil) async {
        guard let currentUser else {
            errorMessage = "Not signed in."
            return
        }
        isSending = true
        errorMessage = nil
        do {
            request = try await requestService.respond(to: request, with: response, text: text, by: currentUser.id)
            counterText = ""
            Haptics.shared.notification(.success)
        } catch {
            errorMessage = "Failed to send response."
            Haptics.shared.notification(.error)
        }
        isSending = false
    }
    
    func sendCounter() async {
        guard !isCounterEmpty else { return }
        await respond(with: .counter, text: counterText)
    }
    
    func saveForLater() async {
        await respond(with: .save)
    }
}

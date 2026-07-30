import Foundation
import Factory

@MainActor
@Observable
final class SpontaneousRequestViewModel {
    private let requestService = Container.shared.requestService()
    private let authService = Container.shared.authService()
    private let relationshipRepository = Container.shared.relationshipRepository()

    var currentUser: User?
    var relationships: [Relationship] = []

    var title: String = ""
    var details: String = ""
    var expiresInMinutes: Int = 20
    var recipientID: String = ""

    var isLoading = false
    var isLoadingPartners = false
    var errorMessage: String?

    var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && !recipientID.isEmpty
    }

    func loadCurrentUserAndPartners() async {
        isLoadingPartners = true
        currentUser = await authService.currentUser()
        if let userID = currentUser?.id {
            do {
                relationships = try await relationshipRepository.fetchRelationships(for: userID)
                if let firstPartner = relationships.first?.participantIDs.first(where: { $0 != userID }) {
                    recipientID = firstPartner
                }
            } catch {
                errorMessage = "Couldn't load partners."
            }
        }
        isLoadingPartners = false
    }

    func sendRequest() async -> Request? {
        guard canSubmit, let currentUser else { return nil }
        isLoading = true
        errorMessage = nil

        let request = Request(
            creatorID: currentUser.id,
            recipientIDs: [recipientID],
            category: .spontaneous,
            title: title.trimmingCharacters(in: .whitespaces),
            details: details.isEmpty ? nil : details,
            proposedTime: Date().addingTimeInterval(TimeInterval(expiresInMinutes * 60))
        )

        do {
            try await requestService.createRequest(request)
            isLoading = false
            Haptics.shared.notification(.success)
            return request
        } catch {
            errorMessage = "Failed to send spontaneous request."
            isLoading = false
            Haptics.shared.notification(.error)
            return nil
        }
    }
}

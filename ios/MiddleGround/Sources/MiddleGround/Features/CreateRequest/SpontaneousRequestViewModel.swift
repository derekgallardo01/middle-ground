import Foundation
import Factory

@MainActor
@Observable
final class SpontaneousRequestViewModel {
    private let requestService = Container.shared.requestService()
    private let authService = Container.shared.authService()
    private let relationshipService = Container.shared.relationshipService()

    var currentUser: User?
    var relationships: [Relationship] = []
    /// relationship.id -> partner display name.
    var displayLabels: [String: String] = [:]

    /// True when the user has groups but nobody has joined any of them yet.
    var needsPartner: Bool {
        !relationships.isEmpty && relationships.allSatisfy { !$0.isPaired }
    }

    func label(for relationship: Relationship) -> String {
        displayLabels[relationship.id] ?? relationship.type.displayName
    }

    var title: String = ""
    var details: String = ""
    var expiresInMinutes: Int = 30
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
                relationships = try await relationshipService.relationships(for: userID)
                displayLabels = await relationshipService.displayLabels(
                    for: relationships, currentUserID: userID
                )
                if let firstPartner = relationships.compactMap({ $0.partnerID(excluding: userID) }).first {
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

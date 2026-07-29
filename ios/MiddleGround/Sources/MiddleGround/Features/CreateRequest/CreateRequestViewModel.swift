import Foundation
import Factory

@MainActor
@Observable
final class CreateRequestViewModel {
    private let requestService = Container.shared.requestService()
    private let authService = Container.shared.authService()
    private let relationshipRepository = Container.shared.relationshipRepository()
    
    var currentUser: User?
    var relationships: [Relationship] = []
    
    var category: RequestCategory
    var title: String
    var details: String
    var proposedTime: Date = Date()
    var includeTime: Bool = false
    var recipientID: String = ""
    
    var isLoading = false
    var isLoadingPartners = false
    var errorMessage: String?
    
    init(category: RequestCategory = .relationship, title: String = "", details: String = "") {
        self.category = category
        self.title = title
        self.details = details
    }
    
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
    
    func createRequest() async -> Request? {
        guard canSubmit, let currentUser else { return nil }
        isLoading = true
        errorMessage = nil
        
        let request = Request(
            creatorID: currentUser.id,
            recipientIDs: [recipientID],
            category: category,
            title: title.trimmingCharacters(in: .whitespaces),
            details: details.isEmpty ? nil : details,
            proposedTime: includeTime ? proposedTime : nil
        )
        
        do {
            try await requestService.createRequest(request)
            isLoading = false
            Haptics.shared.notification(.success)
            return request
        } catch {
            errorMessage = "Failed to send request."
            isLoading = false
            Haptics.shared.notification(.error)
            return nil
        }
    }
}

import Foundation
import Factory

@MainActor
@Observable
final class CreateRequestViewModel {
    private let requestService = Container.shared.requestService()
    private let authService = Container.shared.authService()
    private let relationshipService = Container.shared.relationshipService()

    var currentUser: User?
    var relationships: [Relationship] = []
    /// relationship.id -> partner display name (falls back to the relationship type).
    var displayLabels: [String: String] = [:]

    /// True when the user has relationships but nobody has joined any of them yet.
    var needsPartner: Bool {
        !relationships.isEmpty && relationships.allSatisfy { !$0.isPaired }
    }

    func label(for relationship: Relationship) -> String {
        displayLabels[relationship.id] ?? relationship.type.displayName
    }

    var category: RequestCategory

    // Clamped on assignment rather than checked at submit time, so the cap applies no matter
    // which view binds to it and the user sees the limit as they type instead of losing a
    // long paste at send.
    //
    // Written as a computed property over private storage, NOT `didSet`. Under @Observable the
    // macro rewrites a stored property into a computed one backed by `_title`, so assigning
    // inside its own `didSet` re-enters the setter instead of being suppressed the way plain
    // Swift would — infinite recursion, and the test process dies with SIGSEGV.
    private var titleStorage: String = ""
    var title: String {
        get { titleStorage }
        set { titleStorage = RequestLimits.clamp(newValue, to: RequestLimits.title) }
    }

    private var detailsStorage: String = ""
    var details: String {
        get { detailsStorage }
        set { detailsStorage = RequestLimits.clamp(newValue, to: RequestLimits.details) }
    }

    var proposedTime: Date = Date()
    var includeTime: Bool = false
    var recipientID: String = ""

    var isLoading = false
    var isLoadingPartners = false
    var errorMessage: String?

    init(category: RequestCategory = .relationship, title: String = "", details: String = "") {
        self.category = category
        self.titleStorage = RequestLimits.clamp(title, to: RequestLimits.title)
        self.detailsStorage = RequestLimits.clamp(details, to: RequestLimits.details)
    }

    var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && !recipientID.isEmpty
    }

    func loadCurrentUserAndPartners() async {
        isLoadingPartners = true
        currentUser = await authService.currentUser()
        if let userID = currentUser?.id {
            do {
                relationships = try await relationshipService.relationships(for: userID)
                displayLabels = await relationshipService.displayLabels(for: relationships, currentUserID: userID)
                if let firstPartner = relationships.compactMap({ $0.partnerID(excluding: userID) }).first {
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

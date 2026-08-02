import Foundation
import Factory

@MainActor
@Observable
final class CreateRequestViewModel {
    private let requestService = Container.shared.requestService()
    private let authService = Container.shared.authService()
    private let relationshipService = Container.shared.relationshipService()
    private let venueRepository = Container.shared.venueRepository()

    var currentUser: User?
    var relationships: [Relationship] = []
    /// relationship.id -> partner display name (falls back to the relationship type).
    var displayLabels: [String: String] = [:]

    /// True when the user has relationships but nobody has joined any of them yet.
    var needsPartner: Bool {
        !relationships.isEmpty && relationships.allSatisfy { !$0.isPaired }
    }

    /// Prefills from a template. Nothing is sent — the user still reviews, adds a time if they
    /// want one, and picks who it goes to.
    func apply(_ template: RequestTemplate) {
        title = template.title
        category = template.category
    }

    /// The code to share when nobody has joined yet, so the empty state can offer the share
    /// sheet inline instead of naming the Profile tab it cannot open.
    ///
    /// Nil when several groups are unpaired: `first` picked an arbitrary one, which could invite
    /// someone into a group the user was not thinking about. Profile shows each group's own code.
    var inviteCode: String? {
        let unpaired = relationships.filter { !$0.isPaired }
        return unpaired.count == 1 ? unpaired.first?.inviteCode : nil
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

    private var locationStorage: String = ""
    var location: String {
        get { locationStorage }
        set { locationStorage = RequestLimits.clamp(newValue, to: RequestLimits.location) }
    }

    var proposedTime: Date = Date() {
        didSet { scheduleAvailabilityCheck() }
    }
    var includeTime: Bool = false {
        didSet { scheduleAvailabilityCheck() }
    }

    // MARK: - Calendar clashes

    private let calendarService = Container.shared.calendarConflictService()

    /// Whether the proposed time collides with something already in the user's calendar.
    ///
    /// `.unknown` when access has not been granted, and the UI says nothing in that case — the
    /// one thing this must never do is imply a slot is free when the app simply could not look.
    private(set) var availability: CalendarAvailability = .unknown

    var calendarAccessGranted: Bool { calendarService.hasAccess }

    private var availabilityCheck: Task<Void, Never>?

    /// Coalesces the flurry of updates a date picker emits while the user scrubs through times.
    private func scheduleAvailabilityCheck() {
        availabilityCheck?.cancel()
        guard includeTime, calendarService.hasAccess else {
            availability = .unknown
            return
        }
        let time = proposedTime
        availabilityCheck = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            let result = await calendarService.availability(
                at: time,
                duration: CalendarConflictService.assumedDuration
            )
            guard !Task.isCancelled else { return }
            self.availability = result
        }
    }

    func enableCalendarChecks() async {
        await calendarService.requestAccess()
        scheduleAvailabilityCheck()
    }
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
        await loadVenues()
    }

    // MARK: - Real places, curated

    /// Named places worth suggesting, ordered as the operator curated them.
    ///
    /// Loaded quietly and never blocking: the generic kinds of place are always there, so a
    /// failed or slow read costs a nicety rather than the ability to say where you're going.
    private(set) var venues: [Venue] = []

    /// The ones worth offering for what is being planned right now.
    var suggestedVenues: [Venue] {
        venues.filter { $0.suits(category) }
    }

    private func loadVenues() async {
        venues = (try? await venueRepository.venues()) ?? []
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
            proposedTime: includeTime ? proposedTime : nil,
            location: {
                let trimmed = location.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }()
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

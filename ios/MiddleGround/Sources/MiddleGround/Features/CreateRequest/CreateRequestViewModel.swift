import Foundation
import Factory

@MainActor
@Observable
final class CreateRequestViewModel {
    private let requestService = Container.shared.requestService()
    private let authService = Container.shared.authService()
    private let relationshipService = Container.shared.relationshipService()
    private let userRepository = Container.shared.userRepository()
    private let venueRepository = Container.shared.venueRepository()

    var currentUser: User?
    var relationships: [Relationship] = []
    /// relationship.id -> partner display name (falls back to the relationship type).
    var displayLabels: [String: String] = [:]

    /// True when the user has relationships but nobody has joined any of them yet.
    var needsPartner: Bool { relationships.awaitingSomebody }

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

    /// Shared with the reschedule and counter pickers — see `CalendarClashChecker`, which is
    /// where the debounce and the "could not look is not free" rule now live.
    let clashChecker = CalendarClashChecker()

    var availability: CalendarAvailability { clashChecker.availability }
    var calendarAccessGranted: Bool { clashChecker.accessGranted }

    private func scheduleAvailabilityCheck() {
        clashChecker.check(includeTime ? proposedTime : nil)
    }

    func enableCalendarChecks() async {
        await clashChecker.requestAccess(then: includeTime ? proposedTime : nil)
    }
    // MARK: - Who else is already busy

    private let availabilityRepository = Container.shared.availabilityRepository()

    /// Blocked-out days for the group the plan is going to, keyed by user.
    private var groupAvailability: [SharedAvailability] = []
    private var groupMembers: [String] = []
    private var groupNames: [String: String] = [:]

    /// Who in that group has said they are not free on the chosen day.
    ///
    /// The app has stored this since shared availability shipped and never showed it where a time
    /// is chosen — it lived on the Calendar tab, a screen away from the decision it bears on.
    var busyDay: GroupBusyDay? {
        guard includeTime, let viewerID = currentUser?.id, !groupMembers.isEmpty else { return nil }
        let result = GroupBusyDay.on(
            proposedTime,
            availability: groupAvailability,
            members: groupMembers,
            viewerID: viewerID,
            names: groupNames
        )
        return result.warning == nil ? nil : result
    }

    /// Loads the availability of whichever group the chosen recipient belongs to.
    ///
    /// Best-effort throughout: a failure here costs the warning, never the ability to make a plan.
    func loadGroupAvailability() async {
        guard let viewerID = currentUser?.id, !recipientID.isEmpty else {
            groupAvailability = []
            groupMembers = []
            return
        }
        guard let group = relationships.first(where: { $0.participantIDs.contains(recipientID) }) else {
            groupAvailability = []
            groupMembers = []
            return
        }
        groupMembers = group.participantIDs
        groupAvailability = (try? await availabilityRepository.availability(forGroup: group.id)) ?? []

        var names: [String: String] = [:]
        for id in group.participantIDs where id != viewerID {
            if let user = try? await userRepository.user(id: id) { names[id] = user.name }
        }
        groupNames = names
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

    // MARK: - Nearby, see CreateRequestViewModel+Nearby

    let placeDiscovery: PlaceDiscoveryProvider = Container.shared.placeDiscoveryProvider()
    let locationService = Container.shared.locationService()

    var nearbyPlaces: [DiscoveredPlace] = []
    var nearbyKind: PlaceKind = .restaurant
    var nearbyRadiusMiles: Double = CreateRequestViewModel.defaultRadiusMiles
    var isSearchingNearby = false
    /// Why there is nothing to show — no location, nothing within the radius, a failed search.
    /// Distinct from an empty list, which on its own looks like a bug.
    var nearbyMessage: String?
    /// Set once a search has actually run, so moving the radius does not ask for location on its
    /// own. The tap is what asks.
    var hasSearchedNearby = false
    /// The place taken from the list, kept so a booking link can use its coordinate later.
    var chosenPlace: DiscoveredPlace?

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

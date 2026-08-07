import CoreLocation
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
    /// Whether a person picked the category, as opposed to it being suggested from the recipient.
    ///
    /// Once somebody has chosen, changing who the plan is for must not quietly change what kind of
    /// plan it is underneath them.
    private(set) var categoryWasChosenByHand = false

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
        guard let viewerID = currentUser?.id, !selectedRelationshipID.isEmpty else {
            groupAvailability = []
            groupMembers = []
            return
        }
        // Looked up by id rather than by "which group contains this person", which was ambiguous
        // the moment somebody was in both a couple and a group with the same partner.
        guard let group = relationships.first(where: { $0.id == selectedRelationshipID }) else {
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

    /// Which relationship the plan is being sent to — a couple or a group.
    ///
    /// Was `recipientID`, a single person, and the picker tagged each row with "the first
    /// participant who is not me". With a couple of [me, Sam] and a group of [me, Sam, Priya] that
    /// is `Sam` twice: two rows, one tag, and SwiftUI keeping whichever it saw last. The group was
    /// unselectable, and had it been selectable the plan would have gone to Sam alone under the
    /// group's name.
    ///
    /// Keyed by relationship, because that is what the person is actually choosing.
    var selectedRelationshipID: String = ""

    /// Everybody on the chosen relationship except the person composing.
    ///
    /// One name for a couple, everyone else for a group. `Request.recipientIDs` has always been a
    /// list and the security rules have always worked in `allParticipantIDs`; only compose was
    /// sending to one person.
    var recipients: [String] {
        guard let viewerID = currentUser?.id,
              let relationship = relationships.first(where: { $0.id == selectedRelationshipID })
        else { return [] }
        return relationship.participantIDs.filter { $0 != viewerID }
    }

    var isLoading = false
    var isLoadingPartners = false
    var errorMessage: String?

    init(category: RequestCategory = .relationship, title: String = "", details: String = "") {
        self.category = category
        self.titleStorage = RequestLimits.clamp(title, to: RequestLimits.title)
        self.detailsStorage = RequestLimits.clamp(details, to: RequestLimits.details)
    }

    var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && !recipients.isEmpty
    }

    /// A deliberate choice, which outranks anything suggested from here on.
    func chooseCategory(_ chosen: RequestCategory) {
        // Choosing what is already chosen is not a decision. SwiftUI writes a binding back with
        // its current value often enough that treating every write as a choice would lock the
        // suggestion out before it ever ran.
        guard chosen != category else { return }
        category = chosen
        categoryWasChosenByHand = true
    }

    /// Seeds the category from whoever the plan is addressed to.
    ///
    /// Called when the sheet opens and whenever the recipient changes, because "who" is the best
    /// evidence of "what kind" the app has before anybody types anything.
    func suggestCategoryFromRecipient() {
        guard !categoryWasChosenByHand,
              let relationship = relationships.first(where: { $0.id == selectedRelationshipID })
        else { return }
        category = relationship.type.suggestedRequestCategory
    }

    func loadCurrentUserAndPartners() async {
        isLoadingPartners = true
        currentUser = await authService.currentUser()
        if let userID = currentUser?.id {
            do {
                // Ordered, because the repository's order is not one. It returned the group
                // before the couple here and could return either first tomorrow, which makes
                // "who is this addressed to when the sheet opens" unpredictable — and made a
                // recording of the couple show the group instead.
                //
                // Pairs first, then groups, each alphabetically: the common case leads, and a
                // list of names does not reshuffle itself between launches.
                relationships = try await relationshipService.relationships(for: userID)
                    .sorted { first, second in
                        if first.participantIDs.count != second.participantIDs.count {
                            return first.participantIDs.count < second.participantIDs.count
                        }
                        return first.id < second.id
                    }
                displayLabels = await relationshipService.displayLabels(for: relationships, currentUserID: userID)
                // The first relationship with somebody else in it. A group counts.
                let usable = relationships.filter { relationship in
                    relationship.participantIDs.contains { $0 != userID }
                }
                // A recording that needs to show a group starts on one; see
                // `AppConfiguration.prefersGroupRecipient`.
                let preferred = AppConfiguration.prefersGroupRecipient
                    ? usable.first { $0.participantIDs.count > 2 } ?? usable.first
                    : usable.first
                if let preferred {
                    selectedRelationshipID = preferred.id
                    suggestCategoryFromRecipient()
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
    /// Where the first search was made from, reused by every later one in this sheet.
    ///
    /// Each search asked iOS for a fresh fix, so changing category or nudging the radius by a mile
    /// took another one. That is slower, and it is more location-taking than the feature needs:
    /// nobody moves far enough between two taps of a segmented control to matter.
    var nearbyOrigin: CLLocationCoordinate2D?
    /// The pending re-search, cancelled by whatever changes next.
    ///
    /// The radius is a stepped slider, so dragging it from 1 to 25 fired twenty-four separate
    /// searches — each with its own location request — and the list flickered through every one.
    var nearbySearchTask: Task<Void, Never>?

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
            recipientIDs: recipients,
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

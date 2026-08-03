import Foundation
import Factory

@MainActor
@Observable
final class RequestDetailViewModel {
    private let requestService = Container.shared.requestService()
    private let authService = Container.shared.authService()
    private let gamificationService = Container.shared.gamificationService()
    private let userRepository = Container.shared.userRepository()
    let eventRepository = Container.shared.eventRepository()
    let analytics = Container.shared.analyticsService()
    private let sharedLocationRepository = Container.shared.sharedLocationRepository()
    private let locationService = Container.shared.locationService()
    // Not private: the booking and composer extensions live in their own files, and `private`
    // is file-scoped.
    let reservations = Container.shared.reservationProvider()
    let planOutcomes = Container.shared.planOutcomeRepository()
    let planMessages = Container.shared.planMessageRepository()

    var request: Request
    var currentUser: User?
    // Computed over private storage, not `didSet` — see the note in CreateRequestViewModel:
    // under @Observable a `didSet` that reassigns its own property recurses until the stack
    // overflows.
    private var counterTextStorage: String = ""
    var counterText: String {
        get { counterTextStorage }
        set { counterTextStorage = RequestLimits.clamp(newValue, to: RequestLimits.message) }
    }
    var isSending = false
    var errorMessage: String?
    var partnerName: String?
    /// Names by participant ID, for the group status row and the transcript.
    private(set) var participantNames: [String: String] = [:]

    /// Conversation, live. Kept apart from `request.negotiationChain` because it is stored
    /// apart — see `PlanMessage`.
    var messages: [PlanMessage] = []
    /// The message being replied to, if the composer is aimed at one.
    var replyingToID: String?
    /// Boxed so `deinit` can cancel it. `deinit` on a @MainActor type is nonisolated, so it
    /// cannot touch an isolated stored property — and leaving the Firestore listener running
    /// after the screen closes is a real cost, not a tidiness point.
    let messagesTask = TaskBox()
    var didCancel = false
    var showReschedulePicker = false
    var proposedNewTime = Date().addingTimeInterval(3600)

    /// Sends `.reschedule` with a new proposed time. Until now this response type had an
    /// emoji, label, XP rule, colour and status mapping — and no way to trigger it.
    func sendReschedule() async {
        guard let currentUser else {
            errorMessage = "Not signed in."
            return
        }
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            let previous = request
            request = try await requestService.respond(
                to: request,
                with: .reschedule,
                text: Self.rescheduleText(for: proposedNewTime),
                proposedTime: proposedNewTime,
                by: currentUser.id
            )
            showReschedulePicker = false
            await loadBookingLink()   // the link carries the time, so a new time changes it
            await gamificationService.recordResponse(.reschedule, to: previous, for: currentUser.id)
            Haptics.shared.notification(.success)
        } catch {
            errorMessage = error.localizedDescription
            Haptics.shared.notification(.error)
        }
    }

    // Not private: the composer extension lives in its own file, and `private` is file-scoped.
    static func rescheduleText(for date: Date) -> String {
        "How about \(date.formatted(date: .abbreviated, time: .shortened))?"
    }

    /// Who the viewer is, known on the first frame.
    ///
    /// Everything below only needs the ID, and `authService.currentUserID` has it in memory.
    /// Deriving these from `currentUser` meant waiting on a Firestore fetch of the display
    /// name first: for that half second the view believed it was nobody, so the response row
    /// was missing and every message in the chain rendered as the other person's — grey and
    /// left-aligned — before flipping sides once the name arrived.
    var currentUserID: String? { authService.currentUserID ?? currentUser?.id }

    /// Role-derived UI state. The creator waits; only the recipient answers.
    var canRespond: Bool {
        guard let currentUserID else { return false }
        return request.canRespond(as: currentUserID)
    }

    var isAwaitingResponse: Bool {
        guard let currentUserID else { return false }
        return request.isAwaitingResponse(for: currentUserID)
    }

    var canCancel: Bool {
        guard let currentUserID else { return false }
        return request.canCancel(as: currentUserID)
    }

    var waitingMessage: String {
        "Waiting for \(partnerName ?? "your partner") to respond"
    }

    /// A Maps search for a free-text place name.
    ///
    /// Percent-encoded rather than interpolated: an ampersand or a space in "Joe's Bar & Grill"
    /// would otherwise produce a malformed URL and a link that silently does nothing. Falls back
    /// to Maps itself if encoding somehow fails, so the link is never dead.
    func mapsURL(for place: String) -> URL {
        let encoded = place.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://maps.apple.com/?q=\(encoded)")
            ?? URL(string: "https://maps.apple.com")!
    }

    // MARK: - Inviting someone to just this plan

    /// Whether this plan can be opened up to someone outside your groups.
    var canInviteToPlan: Bool {
        guard let currentUserID else { return false }
        return request.creatorID == currentUserID && request.isOpen
    }

    var planInviteCode: String? {
        request.planInviteCode.flatMap { $0.isEmpty ? nil : $0 }
    }

    func createPlanInvite() async {
        guard let currentUserID else { return }
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            request = try await requestService.createPlanInvite(for: request, by: currentUserID)
            Haptics.shared.impact(.light)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func revokePlanInvite() async {
        guard let currentUserID else { return }
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            request = try await requestService.revokePlanInvite(for: request, by: currentUserID)
            Haptics.shared.impact(.light)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Points on the plan

    var stakeState: StakeState? {
        guard let currentUserID, request.isParticipant(currentUserID) else { return nil }

        guard let stake = request.stake else {
            // Only worth offering on a plan that could still happen.
            return request.isOpen ? .available : nil
        }
        if let settlement = request.stakeSettlement {
            return .settled(settlement, points: stake.points)
        }
        if stake.isAccepted { return .live(points: stake.points) }
        return stake.canAccept(currentUserID)
            ? .awaitingYou(points: stake.points)
            : .awaitingThem(points: stake.points)
    }

    func proposeStake(points: Int) async {
        guard let currentUserID else { return }
        await runStakeAction {
            try await self.requestService.proposeStake(
                on: self.request, points: points, by: currentUserID
            )
        }
    }

    func acceptStake() async {
        guard let currentUserID else { return }
        await runStakeAction {
            try await self.requestService.acceptStake(on: self.request, by: currentUserID)
        }
    }

    private func runStakeAction(_ work: @escaping () async throws -> Request) async {
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            request = try await work()
            Haptics.shared.impact(.light)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Did it happen?

    var needsAttendanceConfirmation: Bool {
        guard let currentUserID else { return false }
        return request.needsConfirmation(from: currentUserID)
    }

    /// How a plan that has been asked about ended up.
    ///
    /// A disagreement is its own outcome rather than a tie broken in someone's favour: one
    /// person cannot record the other as absent, and a contested plan is what an appeal would
    /// argue over, so it settles nothing on its own.
    /// Semantic only — the view supplies the wording, icon and colour, so this stays free of
    /// SwiftUI like the other view models.
    enum AttendanceSummary: Equatable {
        case happened
        case didNotHappen
        case disputed
        case waitingOnThem(String)
    }

    var attendanceSummary: AttendanceSummary? {
        guard let currentUserID, let mine = request.confirmations[currentUserID] else { return nil }
        guard request.everyoneHasAnswered else {
            return .waitingOnThem(partnerName ?? "your partner")
        }
        if request.isDisputed { return .disputed }
        return mine == .happened ? .happened : .didNotHappen
    }

    func confirmAttendance(_ outcome: ConfirmationOutcome) async {
        guard let currentUserID else { return }
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            request = try await requestService.confirmAttendance(
                of: request, outcome: outcome, by: currentUserID
            )
            Haptics.shared.notification(.success)
        } catch {
            errorMessage = error.localizedDescription
            Haptics.shared.notification(.error)
        }
    }

    init(request: Request) {
        self.request = request
        Task { await loadCurrentUser() }
    }

    func loadCurrentUser() async {
        currentUser = await authService.currentUser()
        await loadPartnerName()
        await loadParticipantNames()
        observeMessages()
        await loadSharedLocations()
        await loadBookingLink()
    }

    // MARK: - Location, for the hours around this plan
    //
    // Deliberately narrow. Sharing is only possible while an accepted, dated plan is inside its
    // window, it sends one point rather than starting a feed, and the point is deleted when the
    // window closes. Same rule in `firestore.rules`, because a rule that lives only here is a
    // rule a tampered client does not have.

    /// Everyone's currently-visible points, mine included.
    private(set) var sharedLocations: [SharedLocation] = []
    var isSharingLocation = false

    var canShareLocation: Bool {
        guard let currentUser else { return false }
        return request.canShareLocation(as: currentUser.id)
    }

    var mySharedLocation: SharedLocation? {
        guard let currentUser else { return nil }
        return sharedLocations.first { $0.userID == currentUser.id }
    }

    var partnerSharedLocations: [SharedLocation] {
        sharedLocations.filter { $0.userID != currentUser?.id }
    }

    /// Assigned only by `loadBookingLink()`, in RequestDetailViewModel+Booking.swift.
    var bookingURL: URL?

    func loadSharedLocations() async {
        // Nothing to load outside the window, and no reason to spend a read finding that out.
        guard request.isWithinLocationWindow() else {
            sharedLocations = []
            return
        }
        sharedLocations = (try? await sharedLocationRepository.locations(forRequest: request.id)) ?? []
    }

    func shareLocation() async {
        guard let currentUser, let expiry = request.locationExpiry else { return }
        isSharingLocation = true
        defer { isSharingLocation = false }

        do {
            let coordinate = try await locationService.currentCoordinate()
            let point = SharedLocation(
                userID: currentUser.id,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                sharedAt: Date(),
                expiresAt: expiry
            )
            try await sharedLocationRepository.share(point, forRequest: request.id)
            await loadSharedLocations()
            Haptics.shared.notification(.success)
        } catch {
            errorMessage = error.localizedDescription
            Haptics.shared.notification(.error)
        }
    }

    /// Withdrawing has to work whenever, which is why the rules allow the delete outside the
    /// window too. Being unable to take a location back is the one failure worth designing out.
    func stopSharingLocation() async {
        guard let currentUser else { return }
        isSharingLocation = true
        defer { isSharingLocation = false }
        do {
            try await sharedLocationRepository.stopSharing(
                userID: currentUser.id,
                forRequest: request.id
            )
            await loadSharedLocations()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Resolves the other participant's name so the waiting state can say who we're waiting on.
    private func loadPartnerName() async {
        guard let currentUser,
              let otherID = request.allParticipantIDs.first(where: { $0 != currentUser.id })
        else { return }
        partnerName = (try? await userRepository.user(id: otherID))?.name
    }

    /// Everyone's name, for the group status row. Only fetched for a plan that has a group.
    private func loadParticipantNames() async {
        guard request.isGroupPlan else { return }
        var resolved: [String: String] = [:]
        for id in request.allParticipantIDs {
            if let user = try? await userRepository.user(id: id) {
                resolved[id] = user.name
            }
        }
        participantNames = resolved
    }

    /// Whether calling this off now would be recorded as last-minute.
    ///
    /// Surfaced before the decision, not after it. The reliability score has always counted late
    /// cancellations and never said so at the moment it mattered — you found out later, as a
    /// number on a card, that something you did weeks ago had been held against you.
    var isCancellingLate: Bool { request.isCancellingLate() }

    /// Withdraws the request. Creator-only, enforced again in the service and the rules.
    /// Cancelling keeps the request and records why, rather than deleting it.
    ///
    /// The screen no longer needs to dismiss afterwards — there is still something to look at,
    /// and the other person can see that a plan existed and what happened to it.
    func cancelRequest(reason: CancellationReason?) async -> Bool {
        guard let currentUser else {
            errorMessage = "Not signed in."
            return false
        }
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            request = try await requestService.cancel(request, reason: reason, by: currentUser.id)
            didCancel = true
            Haptics.shared.notification(.success)
            return true
        } catch {
            errorMessage = error.localizedDescription
            Haptics.shared.notification(.error)
            return false
        }
    }

    /// A time attached to the counter being written, if the user picked one.
    var counterProposedTime: Date?

    /// `newTime` moves the proposed time along with the response.
    ///
    /// Without it a counter is text only: "Sunday instead?" changes nothing but the transcript,
    /// so accepting that counter produced an accepted request still carrying the original date —
    /// and a Calendar entry on a day neither person agreed to.
    func respond(with response: ResponseType, text: String? = nil, newTime: Date? = nil) async {
        guard let currentUser else {
            errorMessage = "Not signed in."
            return
        }
        isSending = true
        errorMessage = nil
        do {
            let previous = request
            request = try await requestService.respond(
                to: request,
                with: response,
                text: text,
                proposedTime: newTime,
                by: currentUser.id
            )
            counterText = ""
            // Accepting is what makes the booking link appear; without this it arrives a screen
            // later, for no reason the person can see.
            await loadBookingLink()
            let outcome = await gamificationService.recordResponse(response, to: previous, for: currentUser.id)

            // The same action used to feel completely different depending on where you did
            // it: responding from the feed earned confetti and a haptic, responding from the
            // detail screen silently swapped a status badge. It awards the same XP either way,
            // so it should read the same either way.
            Haptics.shared.feedback(for: response)
            if let unlocked = outcome.newlyUnlocked.first {
                presentCelebration("Achievement unlocked: \(unlocked.title)")
            } else if response == .accept {
                presentCelebration("Request accepted! +\(outcome.xpAwarded) XP")
            } else if response == .negotiate {
                presentCelebration("Let's find a middle ground")
            }
        } catch {
            errorMessage = "Failed to send response."
            Haptics.shared.notification(.error)
        }
        isSending = false
    }

    var showCelebration = false
    var celebrationTitle = ""

    private func presentCelebration(_ title: String) {
        celebrationTitle = title
        showCelebration = true
    }

    // MARK: - Reporting (behaviour in RequestDetailViewModel+Reporting.swift)

    var showReportSheet = false
    var reportReason: ReportReason = .harassment
    private var reportNoteStorage: String = ""
    var reportNote: String {
        get { reportNoteStorage }
        set { reportNoteStorage = RequestLimits.clamp(newValue, to: RequestLimits.reportNote) }
    }
    var didSubmitReport = false

    deinit {
        messagesTask.cancel()
    }
}

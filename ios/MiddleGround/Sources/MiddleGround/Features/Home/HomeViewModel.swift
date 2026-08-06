import Foundation
import Factory

@MainActor
@Observable
final class HomeViewModel {
    private let requestService = Container.shared.requestService()
    private let authService = Container.shared.authService()
    private let gamificationService = Container.shared.gamificationService()
    private let relationshipService = Container.shared.relationshipService()

    var requests: [Request] = []
    var currentUser: User?

    /// Whether anyone has joined yet.
    ///
    /// Home had no relationship dependency at all, so it could not tell an unpaired user from
    /// one who simply had no requests. It told both "Create your first request to get
    /// started" — and for the unpaired user that is a dead end: the compose button they are
    /// being pointed at is disabled, because there is nobody to send to.
    var isPaired = false
    var inviteCode: String?
    var isLoading = false
    /// A failure that leaves nothing to show. Takes over the feed.
    var errorMessage: String?

    /// A failure that happened *to* something on screen, which the feed must survive.
    ///
    /// Responding from a card can fail while the list around it is perfectly good, so this is
    /// presented as an alert rather than replacing the feed with an error state.
    var responseErrorMessage: String?

    // Whether the first load has actually answered each question the feed asks.
    //
    // Both start false and `isPaired` starts false too, so on the very first frame the feed
    // concluded "no requests, not paired" and drew the invite prompt — telling someone who has
    // a partner to go and find one, for as long as the network took. Tracked separately
    // because `init` and the view's `.task` load these concurrently: knowing the requests have
    // arrived says nothing about whether the pairing state has.
    private(set) var hasLoadedRequests = false
    private(set) var hasLoadedRelationship = false

    /// True once the feed can distinguish "empty because nobody has joined you" from
    /// "empty because you have no requests yet". Until then it must draw neither.
    var hasLoaded: Bool { hasLoadedRequests && hasLoadedRelationship }
    var showCelebration = false
    var celebrationTitle = ""

    // No loading in `init`, deliberately.
    //
    // This used to start three sequential fetches here, and `HomeView.task` then ran
    // `loadRequests()` again before subscribing — so one appearance issued the same unbounded
    // request query three times. Measured over a scripted walkthrough it fired six times.
    //
    // SwiftUI also re-evaluates `@State private var viewModel = HomeViewModel()` whenever the
    // view struct is rebuilt; the extra instance is discarded, but any `Task` its initialiser
    // already started runs to completion regardless. Work in a view model's `init` is work you
    // cannot see and cannot cancel.

    /// The viewer's ID, straight from the in-memory session — no await, no network.
    ///
    /// Everything on this screen needs the ID; only the greeting needs the *name*. Fetching the
    /// user document to learn an ID the app already holds cost a full round trip on every
    /// appearance, and made the ID arrive late enough that the response row was missing on the
    /// first frame. `RequestDetailViewModel` has done it this way for a while.
    private var userID: String? { authService.currentUserID ?? currentUser?.id }

    /// Resolves the display name for the greeting. Deliberately not awaited by anything —
    /// "Hello, there" becoming "Hello, Alex" a moment later costs nothing.
    func loadCurrentUser() async {
        currentUser = await authService.currentUser()
    }

    /// Reads pairing state so the empty state can tell the truth.
    ///
    /// Failures leave the previous values alone rather than defaulting to "unpaired" — a
    /// transient error should not tell a paired user to go and find a partner.
    func loadRelationshipState() async {
        guard let userID else { return }
        guard let relationships = try? await relationshipService.relationships(for: userID) else {
            // Still resolved, just unsuccessfully — otherwise a user whose relationship fetch
            // fails sits on the skeleton forever.
            hasLoadedRelationship = true
            return
        }
        isPaired = relationships.contains(where: \.isPaired)
        // Only when one group could own it. With several unpaired groups `first` picked an
        // arbitrary one, so this prompt could hand out the code for a group the user was not
        // thinking about. Nil here makes InvitePrompt point at Profile, where each group shows
        // its own code.
        let unpaired = relationships.filter { !$0.isPaired }
        inviteCode = unpaired.count == 1 ? unpaired.first?.inviteCode : nil
        hasLoadedRelationship = true
    }

    func loadRequests() async {
        guard let userID else {
            errorMessage = "Not signed in."
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            requests = try await LoadTimer.measure("home.requests") {
                try await requestService.fetchRequests(for: userID)
            }
        } catch {
            errorMessage = "Couldn't load requests. Pull to try again."
        }
        isLoading = false
        hasLoadedRequests = true
    }

    /// Streams live updates. Runs for the lifetime of the view via `.task`.
    func observeRequests() async {
        guard let userID else { return }
        // Timed on first delivery only. The listener then stays open for the life of the screen,
        // so timing the whole stream would measure how long the screen was open — and comparing
        // that to the old one-shot fetch would be meaningless.
        var isFirstDelivery = true
        let started = ContinuousClock.now
        for await updated in requestService.observeRequests(for: userID) {
            if isFirstDelivery {
                isFirstDelivery = false
                LoadTimer.record("home.requests", since: started)
            }
            requests = updated
            isLoading = false
            hasLoadedRequests = true
        }
    }

    /// Whether the signed-in user may respond to this request (recipient, still pending).
    func canRespond(to request: Request) -> Bool {
        guard let userID else { return false }
        return request.canRespond(as: userID)
    }

    /// Narrows the feed. Saved requests were reachable only by scrolling past everything else.
    ///
    /// "Save for later" set the status to `.saved` and then offered no way to find what you had
    /// saved — the whole point of setting something aside is retrieving it later. Nothing else
    /// changes: a saved request is still fully answerable, because a save deliberately does not
    /// consume your turn (both `awaitingResponseFrom` and `isMyTurn` in the rules skip them).
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case yourTurn = "Your turn"
        case saved = "Saved"

        var id: String { rawValue }
    }

    var filter: Filter = .all

    var visibleRequests: [Request] {
        switch filter {
        case .all: return requests
        case .yourTurn:
            guard let userID else { return [] }
            return requests.filter { $0.canRespond(as: userID) }
        case .saved: return requests.filter { $0.status == .saved }
        }
    }

    /// Hidden until there is something to find, so the control never appears on an empty feed.
    var showsFilter: Bool {
        requests.count > 3 || requests.contains { $0.status == .saved }
    }

    var savedCount: Int { requests.filter { $0.status == .saved }.count }

    /// How many requests are actually waiting on an answer from you.
    ///
    /// The header used to count `isPending`, which is `status == .pending` and so only ever
    /// counted requests nobody had replied to yet. Once the turn-taking model landed, a
    /// request you had been countered on was — correctly — no longer `.pending`, so the one
    /// thing most in need of your attention was the one thing the header would not count. A
    /// three-turn negotiation sitting on your turn read as "Nothing waiting on you".
    var awaitingYouCount: Int {
        guard let userID else { return 0 }
        return requests.filter { $0.canRespond(as: userID) }.count
    }

    /// Requests with a response in flight, so their card can show progress and refuse a
    /// second tap. Keyed by id rather than a single flag because the feed shows many cards
    /// and only the one you tapped should change.
    private(set) var respondingTo: Set<String> = []

    func isResponding(to request: Request) -> Bool {
        respondingTo.contains(request.id)
    }

    func respond(to request: Request, with response: ResponseType) {
        // `userID`, not `currentUser`: the display name arrives on its own schedule now, and
        // gating the primary action on it would mean an Accept tapped early did nothing at all.
        guard let userID else { return }
        // Guards against the double-tap window: there was previously no in-flight state at
        // all here, so a slow network let the same response fire repeatedly.
        guard !respondingTo.contains(request.id) else { return }
        respondingTo.insert(request.id)

        Task {
            defer { respondingTo.remove(request.id) }
            do {
                let updated = try await requestService.respond(to: request, with: response, by: userID)
                if let index = requests.firstIndex(where: { $0.id == updated.id }) {
                    requests[index] = updated
                }

                // Award XP / streak / achievements. Home no longer displays the totals — they
                // live on Activities — but the celebration still reports what this response
                // earned, from the outcome rather than from stored state.
                let outcome = await gamificationService.recordResponse(response, to: request, for: userID)
                celebrate(response: response, outcome: outcome)
            } catch {
                // Deliberately *not* `errorMessage`. That one takes over the feed, and the view
                // only renders it when `requests.isEmpty` — which a failed response cannot be,
                // since responding requires a request to respond to. So this message was set and
                // could never be read: the row simply snapped back and nothing said why.
                responseErrorMessage = UserFacingError.message(for: error)
            }
        }
    }

    private func celebrate(response: ResponseType, outcome: GamificationOutcome) {
        // One haptic, fired here once the response has actually landed. The card used to fire
        // its own on tap as well, so accepting from the feed buzzed twice — and buzzed
        // "success" before the network had confirmed anything.
        Haptics.shared.feedback(for: response)

        if let unlocked = outcome.newlyUnlocked.first {
            presentCelebration("Achievement unlocked: \(unlocked.title)")
        } else if response == .accept {
            presentCelebration("Request accepted! +\(outcome.xpAwarded) XP")
        } else if response == .negotiate {
            presentCelebration("Let's find a middle ground")
        }
    }

    private func presentCelebration(_ title: String) {
        celebrationTitle = title
        showCelebration = true
    }
}

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
    var errorMessage: String?

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

    init() {
        Task {
            await loadCurrentUser()
            await loadRelationshipState()
            await loadRequests()
        }
    }

    func loadCurrentUser() async {
        currentUser = await authService.currentUser()
    }

    /// Reads pairing state so the empty state can tell the truth.
    ///
    /// Failures leave the previous values alone rather than defaulting to "unpaired" — a
    /// transient error should not tell a paired user to go and find a partner.
    func loadRelationshipState() async {
        guard let currentUser else { return }
        guard let relationships = try? await relationshipService.relationships(for: currentUser.id) else {
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
        guard let currentUser else {
            errorMessage = "Not signed in."
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            requests = try await requestService.fetchRequests(for: currentUser.id)
        } catch {
            errorMessage = "Couldn't load requests. Pull to try again."
        }
        isLoading = false
        hasLoadedRequests = true
    }

    /// Streams live updates. Runs for the lifetime of the view via `.task`.
    func observeRequests() async {
        if currentUser == nil { await loadCurrentUser() }
        guard let currentUser else { return }
        for await updated in requestService.observeRequests(for: currentUser.id) {
            requests = updated
            isLoading = false
            hasLoadedRequests = true
        }
    }

    /// Whether the signed-in user may respond to this request (recipient, still pending).
    func canRespond(to request: Request) -> Bool {
        guard let currentUser else { return false }
        return request.canRespond(as: currentUser.id)
    }

    /// How many requests are actually waiting on an answer from you.
    ///
    /// The header used to count `isPending`, which is `status == .pending` and so only ever
    /// counted requests nobody had replied to yet. Once the turn-taking model landed, a
    /// request you had been countered on was — correctly — no longer `.pending`, so the one
    /// thing most in need of your attention was the one thing the header would not count. A
    /// three-turn negotiation sitting on your turn read as "Nothing waiting on you".
    var awaitingYouCount: Int {
        guard let currentUser else { return 0 }
        return requests.filter { $0.canRespond(as: currentUser.id) }.count
    }

    /// Requests with a response in flight, so their card can show progress and refuse a
    /// second tap. Keyed by id rather than a single flag because the feed shows many cards
    /// and only the one you tapped should change.
    private(set) var respondingTo: Set<String> = []

    func isResponding(to request: Request) -> Bool {
        respondingTo.contains(request.id)
    }

    func respond(to request: Request, with response: ResponseType) {
        guard let currentUser else { return }
        // Guards against the double-tap window: there was previously no in-flight state at
        // all here, so a slow network let the same response fire repeatedly.
        guard !respondingTo.contains(request.id) else { return }
        respondingTo.insert(request.id)

        Task {
            defer { respondingTo.remove(request.id) }
            do {
                let updated = try await requestService.respond(to: request, with: response, by: currentUser.id)
                if let index = requests.firstIndex(where: { $0.id == updated.id }) {
                    requests[index] = updated
                }

                // Award XP / streak / achievements. Home no longer displays the totals — they
                // live on Activities — but the celebration still reports what this response
                // earned, from the outcome rather than from stored state.
                let outcome = await gamificationService.recordResponse(response, to: request, for: currentUser.id)
                celebrate(response: response, outcome: outcome)
            } catch {
                errorMessage = "Failed to send response."
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

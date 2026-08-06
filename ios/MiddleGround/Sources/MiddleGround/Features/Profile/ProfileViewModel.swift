import Foundation
import UIKit
import Factory

@MainActor
@Observable
final class ProfileViewModel {
    private let analytics = Container.shared.analyticsService()
    private let authService = Container.shared.authService()
    private let gamificationService = Container.shared.gamificationService()
    private let notificationService = NotificationService.shared
    private let notificationSettingsRepository = Container.shared.notificationSettingsRepository()
    private let relationshipService = Container.shared.relationshipService()
    private let requestService = Container.shared.requestService()
    private let signInManager = Container.shared.signInWithAppleManager()

    var user: User?
    var stats: GamificationStats?
    var notificationsEnabled = false
    var notificationSettings = NotificationSettings()
    var relationships: [Relationship] = []

    var unpairedRelationships: [Relationship] { relationships.filter { !$0.isPaired } }

    // MARK: - Seeing someone else's reliability
    //
    // Deliberately not inside a couple. A reliability number your partner can quote back at you
    // stops being feedback and becomes an argument, so partners keep theirs private while
    // groups — where a no-show costs someone else their evening or their booking — do not.
    //
    // Computed from the plans you actually share, not from that person's whole history. It is
    // the only thing the security rules let you read anyway, and it is the more honest number:
    // how reliably plans *with you* happen, rather than a reputation formed elsewhere.

    /// The other member's reliability, keyed by relationship ID. Empty for couples.
    private(set) var memberReliability: [String: ReliabilityScore] = [:]

    /// Records that somebody reached for the share sheet on an invite code.
    ///
    /// `ShareLink` reports nothing back, so this is the tap and not a completed share — which is
    /// what the event is named for. It is still the only denominator available: without it the
    /// only invite signal is the ones that worked.
    func noteInviteShared(relationshipID: String?) {
        guard let user else { return }
        Task {
            await analytics.track(
                .inviteShared,
                userID: user.id,
                relationshipID: relationshipID,
                metadata: ["kind": "group"]
            )
        }
    }

    /// Defers to `ReliabilityScore.canBeSeen` — the rule belongs with the score, not with one
    /// screen that happens to show it.
    func canSeeReliability(in relationship: Relationship) -> Bool {
        ReliabilityScore.canBeSeen(in: relationship)
    }

    private func loadMemberReliability() async {
        guard let user else { return }
        let visible = relationships.filter { canSeeReliability(in: $0) }
        guard !visible.isEmpty,
              let requests = try? await requestService.fetchRequests(for: user.id) else {
            memberReliability = [:]
            return
        }

        var scores: [String: ReliabilityScore] = [:]
        for relationship in visible {
            guard let otherID = relationship.partnerID(excluding: user.id) else { continue }
            let shared = requests.filter { $0.isParticipant(otherID) }
            scores[relationship.id] = ReliabilityScore.from(requests: shared, userID: otherID)
        }
        memberReliability = scores
    }

    /// The prominent code, shown only when there is exactly one group it could belong to.
    ///
    /// This used to be `relationships.first { !$0.isPaired }?.inviteCode`, which with more than
    /// one unpaired group picked an arbitrary one — so the screen could show the code for a
    /// different group than the user believed they were inviting to, and the invitee would land
    /// somewhere unexpected. With several, the per-group rows carry their own codes instead and
    /// this stays nil rather than guessing.
    var soleInviteCode: String? {
        unpairedRelationships.count == 1 ? unpairedRelationships.first?.inviteCode : nil
    }

    var isPaired: Bool { relationships.contains(where: \.isPaired) }

    /// No group at all — reachable by quitting during onboarding, or after a partner deletes
    /// their account. Before this there was no way back: relationships could only ever be
    /// created inside onboarding, which an authenticated user never sees again.
    var hasNoRelationship: Bool { relationships.isEmpty }

    var joinCodeInput: String = ""
    var isPairing = false
    var selectedRelationshipType: RelationshipType = .couple

    var canJoin: Bool {
        Relationship.normalizeInviteCode(joinCodeInput).count == Relationship.inviteCodeLength
    }

    /// Creates a group so the user has something to share a code for.
    func createGroup() async {
        guard let user else { return }
        isPairing = true
        errorMessage = nil
        defer { isPairing = false }
        do {
            _ = try await relationshipService.createRelationship(
                type: selectedRelationshipType, ownerID: user.id
            )
            await loadRelationships()
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    /// Redeems someone else's invite code.
    /// Redeems a code, whichever kind it is.
    ///
    /// Group codes and single-plan codes look identical and come from the same collection, so
    /// asking someone to know which they were handed would be asking them to know something the
    /// sender never told them. Group first, because that is the far more common case; a plan
    /// code simply is not a group code, and falling through costs one lookup.
    func joinGroup() async {
        guard let user else { return }
        isPairing = true
        errorMessage = nil
        defer { isPairing = false }
        var groupFailure: Error?
        do {
            _ = try await relationshipService.join(inviteCode: joinCodeInput, userID: user.id)
            joinCodeInput = ""
            await loadRelationships()
            return
        } catch {
            guard JoinCodeFailure.isWorthTryingAsPlan(afterGroupFailure: error) else {
                // The code *did* name a group, and the join was refused for a reason worth
                // hearing. A plan lookup can only overwrite that with something less true.
                errorMessage = UserFacingError.message(for: error)
                return
            }
            groupFailure = error
        }

        do {
            try await requestService.joinPlan(inviteCode: joinCodeInput, userID: user.id)
            joinCodeInput = ""
            didJoinPlan = true
        } catch {
            errorMessage = JoinCodeFailure.message(
                groupFailure: groupFailure ?? error,
                planFailure: error
            )
        }
    }

    /// Set when a code turned out to be for a single plan, so the UI can point at Requests
    /// rather than leaving someone on Profile wondering what happened.
    var didJoinPlan = false
    var isLoading = false
    var isDeletingAccount = false
    var errorMessage: String?

    var levelDisplay: String {
        guard let stats else { return "" }
        return "Level \(stats.level) · \(stats.relationshipXP.formatted()) XP"
    }

    // No loading in `init`. Between this, `.task` and the `scenePhase` hook, `refresh()` ran
    // three times on a single appearance — measured at six times across one walkthrough — and
    // each run is four sequential network calls plus an invite-repair loop plus a second
    // relationship fetch. `.task` is now the only entry point on appear.

    /// Reloads everything this screen shows.
    ///
    /// Called on appear, on pull-to-refresh, and when the app returns to the foreground —
    /// because the state that matters most here (has someone joined my group?) changes
    /// remotely, without this device doing anything.
    func refresh() async {
        await LoadTimer.measure("profile.refresh") {
            // The user has to land first — the other three each need an ID. After that they are
            // mutually independent, and running them in sequence meant paying for three round
            // trips to do the work of one.
            await loadUser()
            async let stats: Void = loadStats()
            async let relationships: Void = loadRelationships()
            async let notifications: Void = checkNotificationStatus()
            _ = await (stats, relationships, notifications)
        }
    }

    func loadRelationships() async {
        guard let user else { return }
        do {
            relationships = try await relationshipService.relationships(for: user.id)
        } catch {
            // Keep whatever we already had. This used to be `try? ... ?? []`, so a transient
            // network failure emptied the array, `hasNoRelationship` flipped true, and a
            // perfectly well-paired user was shown the "You're not connected with anyone yet"
            // prompt — inviting them to create a second group.
            MGLog.storage.error("Could not load relationships: \(error.localizedDescription, privacy: .public)")
        }
        await repairInviteIfNeeded()
        await loadMemberReliability()
    }

    /// Republishes the invite document when the displayed code no longer resolves.
    ///
    /// Reachable after the group's owner leaves: they revoke their code on the way out, which
    /// would otherwise leave the remaining member showing a code nobody can redeem.
    private func repairInviteIfNeeded() async {
        guard let user else { return }
        // Every unpaired group this user owns, not just whichever came back first — with more
        // than one, repairing only the first left the others showing codes nobody can redeem.
        let owned = unpairedRelationships.filter { $0.participantIDs.first == user.id }
        guard !owned.isEmpty else { return }

        var repairedAny = false
        for relationship in owned {
            if let repaired = try? await relationshipService.repairInvite(
                for: relationship, userID: user.id
            ), repaired != relationship.inviteCode {
                repairedAny = true
            }
        }
        guard repairedAny else { return }
        relationships = (try? await relationshipService.relationships(for: user.id)) ?? relationships
    }

    // MARK: - Leaving

    var isLeavingGroup = false

    /// Removes the user from a group.
    ///
    /// The only way out short of deleting the whole account — which is what App Review
    /// guideline 1.2 wants as the "block an abusive user" path, and what anyone whose
    /// relationship ends needs regardless.
    func leaveGroup(_ relationship: Relationship) async -> Bool {
        guard let user else { return false }
        isLeavingGroup = true
        errorMessage = nil
        defer { isLeavingGroup = false }
        do {
            try await relationshipService.leave(relationshipID: relationship.id, userID: user.id)
            await loadRelationships()
            return true
        } catch {
            errorMessage = UserFacingError.message(for: error)
            return false
        }
    }

    /// Issues a new invite code for a specific group, retiring the old one.
    ///
    /// Takes the group explicitly. Choosing it internally meant rotating whichever unpaired
    /// group happened to be first, which with several is not necessarily the one on screen.
    func regenerateInviteCode(for relationship: Relationship) async {
        guard let user else { return }
        isPairing = true
        errorMessage = nil
        defer { isPairing = false }
        do {
            _ = try await relationshipService.regenerateInviteCode(for: relationship, userID: user.id)
            await loadRelationships()
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    // MARK: - Renaming

    var relationshipToRename: Relationship?
    var renameInput = ""

    func beginRenaming(_ relationship: Relationship) {
        relationshipToRename = relationship
        renameInput = relationship.name ?? ""
    }

    /// Any participant may rename — it is a shared label, not the owner's.
    func commitRename() async {
        guard let relationship = relationshipToRename else { return }
        relationshipToRename = nil
        do {
            try await relationshipService.rename(relationship, to: renameInput)
            await loadRelationships()
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
        renameInput = ""
    }

    func loadUser() async {
        user = await authService.currentUser()
    }

    func loadStats() async {
        guard let user else { return }
        stats = await gamificationService.stats(for: user.id)
    }

    func checkNotificationStatus() async {
        await notificationService.checkAuthorizationStatus()
        notificationsEnabled = notificationService.hasPermission
        if notificationsEnabled { await loadNotificationSettings() }
    }

    // MARK: - Which notifications

    /// Loaded rather than assumed, and unchanged on failure.
    ///
    /// A failed read leaves every switch on, which matches what the backend does with a document
    /// it cannot read. Showing a switch as on while the server has it off is the smaller lie:
    /// the alternative is showing everything off and having the user tap one, which writes it
    /// back on and quietly discards whatever else they had muted.
    func loadNotificationSettings() async {
        guard let user else { return }
        guard let loaded = try? await notificationSettingsRepository.settings(for: user.id) else {
            return
        }
        notificationSettings = loaded
    }

    func isEnabled(_ kind: NotificationKind) -> Bool {
        notificationSettings.isEnabled(kind)
    }

    /// Writes immediately, and reverts the switch if the write fails.
    ///
    /// Optimistic because a switch that waits for a round trip before moving feels broken. The
    /// revert is what keeps that honest: a mute that silently failed to save would leave someone
    /// certain they had turned something off while it kept arriving.
    func setEnabled(_ kind: NotificationKind, _ enabled: Bool) async {
        guard let user else { return }
        let previous = notificationSettings
        notificationSettings.set(kind, enabled: enabled)
        do {
            try await notificationSettingsRepository.save(notificationSettings, for: user.id)
        } catch {
            notificationSettings = previous
            errorMessage = "Couldn't save that. Check your connection and try again."
        }
    }

    /// iOS has no API to revoke notification permission, so turning it off opens Settings.
    func toggleNotifications() async {
        if notificationsEnabled {
            openSystemSettings()
        } else {
            _ = await notificationService.requestAuthorization()
            await checkNotificationStatus()
        }
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// Deletes the account for good.
    ///
    /// Apple requires the Sign in with Apple token to be revoked on deletion, and revocation
    /// needs a *fresh* single-use authorization code — so this re-presents the Apple sheet
    /// before deleting. Anonymous test accounts have no Apple credential and skip straight
    /// to deletion.
    func deleteAccount() async -> Bool {
        isDeletingAccount = true
        errorMessage = nil
        defer { isDeletingAccount = false }

        await notificationService.removeTokenForCurrentUser()

        let authorizationCode = await freshAppleAuthorizationCode()
        do {
            try await authService.deleteAccount(appleAuthorizationCode: authorizationCode)
            LocalStore.shared.purgeAll()
            return true
        } catch {
            errorMessage = "Couldn't delete your account. Please try again."
            return false
        }
    }

    /// Re-runs Sign in with Apple purely to obtain a revocation code. Returns nil if the
    /// user cancels or the account isn't Apple-backed; deletion still proceeds.
    private func freshAppleAuthorizationCode() async -> String? {
        await withCheckedContinuation { continuation in
            signInManager.signIn { result in
                switch result {
                case .success(let apple): continuation.resume(returning: apple.authorizationCode)
                case .failure: continuation.resume(returning: nil)
                }
            }
        }
    }

    func signOut() async -> Bool {
        isLoading = true
        await NotificationService.shared.removeTokenForCurrentUser()
        do {
            try await authService.signOut()
            // Derived, per-account data must not outlive the session on a shared device.
            LocalStore.shared.purgeAll()
            isLoading = false
            return true
        } catch {
            errorMessage = UserFacingError.message(for: error)
            isLoading = false
            return false
        }
    }
}

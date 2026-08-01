import Foundation
import UIKit
import Factory

@MainActor
@Observable
final class ProfileViewModel {
    private let authService = Container.shared.authService()
    private let gamificationService = Container.shared.gamificationService()
    private let notificationService = NotificationService.shared
    private let relationshipService = Container.shared.relationshipService()
    private let requestService = Container.shared.requestService()
    private let signInManager = Container.shared.signInWithAppleManager()

    var user: User?
    var stats: GamificationStats?
    var notificationsEnabled = false
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

    func canSeeReliability(in relationship: Relationship) -> Bool {
        relationship.type != .couple && relationship.isPaired
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
        Relationship.normalizeInviteCode(joinCodeInput).count >= 6
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
            errorMessage = error.localizedDescription
        }
    }

    /// Redeems someone else's invite code.
    func joinGroup() async {
        guard let user else { return }
        isPairing = true
        errorMessage = nil
        defer { isPairing = false }
        do {
            _ = try await relationshipService.join(inviteCode: joinCodeInput, userID: user.id)
            joinCodeInput = ""
            await loadRelationships()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    var isLoading = false
    var isDeletingAccount = false
    var errorMessage: String?

    var levelDisplay: String {
        guard let stats else { return "" }
        return "Level \(stats.level) · \(stats.relationshipXP.formatted()) XP"
    }

    init() {
        Task { await refresh() }
    }

    /// Reloads everything this screen shows.
    ///
    /// Called on appear, on pull-to-refresh, and when the app returns to the foreground —
    /// because the state that matters most here (has someone joined my group?) changes
    /// remotely, without this device doing anything.
    func refresh() async {
        await loadUser()
        await loadStats()
        await loadRelationships()
        await checkNotificationStatus()
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
            errorMessage = error.localizedDescription
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
            errorMessage = error.localizedDescription
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
            errorMessage = error.localizedDescription
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
            errorMessage = error.localizedDescription
            isLoading = false
            return false
        }
    }
}

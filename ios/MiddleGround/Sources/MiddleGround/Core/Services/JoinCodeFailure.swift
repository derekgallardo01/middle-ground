import Foundation

/// Which failure to report when one code is tried as two kinds of code.
///
/// Group codes and plan codes look identical and come from the same collection, so the join field
/// tries the code as a group first and falls through to a plan. That fall-through is right, and it
/// made every message wrong: whatever the *second* attempt said was reported, so a group problem
/// came back as "That invite code doesn't match a plan." — naming a distinction the sender never
/// made, about the attempt the person never asked for.
///
/// Two questions, kept here rather than in the view model so they can be answered without one.
enum JoinCodeFailure {

    /// Which kind the code turned out to be.
    enum Outcome: Equatable {
        case joinedGroup
        case joinedPlan
    }

    /// Tries a code as a group, then as a plan, and throws the failure worth reporting.
    ///
    /// The order was written twice — once in Profile, once in onboarding — and the two drifted:
    /// Profile learned to stop when the group lookup gave a real verdict, and onboarding kept
    /// falling through on *any* failure, so typing your own code there answered "that invite code
    /// doesn't match a plan" about a code that named a group perfectly well. One copy, called by
    /// both, is the fix for the class rather than the instance.
    ///
    /// Closures rather than the services themselves, so this is testable without either — the
    /// view models cannot be built outside an app host at all (`NotificationService` reaches for
    /// `UNUserNotificationCenter`), which is exactly why neither screen's version was ever tested.
    static func join(
        group: () async throws -> Void,
        plan: () async throws -> Void
    ) async throws -> Outcome {
        do {
            try await group()
            return .joinedGroup
        } catch let groupFailure {
            guard isWorthTryingAsPlan(afterGroupFailure: groupFailure) else { throw groupFailure }
            do {
                try await plan()
                return .joinedPlan
            } catch let planFailure {
                throw combined(groupFailure: groupFailure, planFailure: planFailure)
            }
        }
    }

    /// Whether a group lookup that failed leaves the plan attempt worth making.
    ///
    /// Only `codeNotFound` does. `alreadyJoined` and `ownCode` both mean the code *did* name a
    /// group — the lookup succeeded and the join was refused — so there is nothing a plan lookup
    /// could add, and its answer would replace a true statement with a false one.
    static func isWorthTryingAsPlan(afterGroupFailure error: Error) -> Bool {
        guard let pairingError = error as? RelationshipService.PairingError else {
            // Anything else is a network or permission failure rather than a verdict on the code.
            // Trying the plan costs one lookup and may still succeed.
            return true
        }
        return pairingError == .codeNotFound
    }

    /// What to say once both attempts have failed.
    ///
    /// When both simply found nothing, the honest message is the one that doesn't name a kind:
    /// the field takes either, and the person typing has no way to know which they were handed.
    /// A plan failure that says something more specific than "not found" is kept, because then
    /// the code *was* a plan code and something else went wrong.
    static func message(groupFailure: Error, planFailure: Error) -> String? {
        UserFacingError.message(
            for: combined(groupFailure: groupFailure, planFailure: planFailure)
        )
    }

    /// The same verdict as an error, for callers that throw rather than assign a message.
    ///
    /// Onboarding is one: it wraps the whole step in a `do`/`catch` and reports whatever comes
    /// out. Without this it had its own naive fall-through — any group failure at all led to a
    /// plan lookup — so typing your own code answered "that invite code doesn't match a plan"
    /// about a code that matched a group perfectly well.
    static func combined(groupFailure: Error, planFailure: Error) -> Error {
        let bothMerelyMissing = (groupFailure as? RelationshipService.PairingError) == .codeNotFound
            && (planFailure as? RequestError) == .inviteNotFound

        return bothMerelyMissing ? RelationshipService.PairingError.codeNotFound : planFailure
    }
}

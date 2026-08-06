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
        let bothMerelyMissing = (groupFailure as? RelationshipService.PairingError) == .codeNotFound
            && (planFailure as? RequestError) == .inviteNotFound

        if bothMerelyMissing {
            return UserFacingError.message(for: RelationshipService.PairingError.codeNotFound)
        }
        return UserFacingError.message(for: planFailure)
    }
}

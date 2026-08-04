import Foundation

/// Collecting what a finished plan was worth.
///
/// Its own file for the same reason as the booking, composer, message and reporting extensions:
/// the view model sits at the 500-line limit and every screen concern that can stand alone should.
extension RequestDetailViewModel {
    /// Pays out a plan whose outcome is settled, if it has not been paid already.
    ///
    /// Called both after confirming and on opening the screen, because the two people on a plan
    /// do not settle at the same moment: whoever answers last triggers it, and whoever answered
    /// first is not on screen to be paid. The service is idempotent, so the second call is free.
    func settleIfNeeded() async {
        guard let currentUserID else { return }
        guard let outcome = await gamificationService.recordAttendance(of: request, for: currentUserID) else {
            return
        }
        if let unlocked = outcome.newlyUnlocked.first {
            presentCelebration("Achievement unlocked: \(unlocked.title)")
        } else if outcome.xpAwarded > 0 {
            presentCelebration("You turned up! +\(outcome.xpAwarded) XP")
        }
    }
}

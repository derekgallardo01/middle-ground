import Foundation

/// Whether this plan has gone quiet, and who has said they are still coming.
///
/// The gap this fills is between agreeing and the day. `remindBeforePlan` pushes "Still on?"
/// sixteen hours before and `promptForAttendance` asks "did it happen?" four hours after; in
/// between, a plan three weeks out gets nothing for twenty days. That push also asked a question
/// nothing could answer, because no control anywhere meant "yes, I'm still in".
extension RequestDetailViewModel {

    var momentum: PlanMomentum {
        PlanMomentum.from(request: request)
    }

    /// Whether to show the check-in at all.
    ///
    /// Two reasons to be here, and the second was missing. A plan that has gone quiet needs the
    /// prompt — but a plan somebody has already answered needs the *answers*, and saying you are
    /// still in resets the silence, so `wantsCheckIn` turns false the instant anybody taps. The
    /// row therefore vanished on tap: no acknowledgement that it registered, and the ticks saying
    /// who is coming disappeared with it. The `hasAnswered` branch was unreachable.
    ///
    /// Found by a UI test, not by reading this. It is exactly the shape that looks right.
    var showsStillOn: Bool {
        guard let currentUserID, request.canSayStillOn(as: currentUserID) else { return false }
        return momentum.wantsCheckIn || !request.stillOn.isEmpty
    }

    /// Whether *this* person has already answered the current round.
    var hasSaidStillOn: Bool {
        guard let currentUserID else { return false }
        return request.hasCurrentStillOn(from: currentUserID)
    }

    /// Names of everyone whose yes is current, you first.
    ///
    /// Named rather than counted, deliberately. Showing who is in makes the last person visible,
    /// which is the trade the ticks were chosen for — but it says nothing about anybody's
    /// character. It is one fact about one evening, with no score attached and nothing carried
    /// forward, which is what keeps it clear of the rule that couples are never ranked.
    var stillOnNames: [String] {
        // Everyone but you. Your own answer is the tick above the list — listing you as well
        // printed "You said you're still in" and "You are still in", one under the other.
        namesFor(
            request.allParticipantIDs.filter {
                $0 != currentUserID && request.hasCurrentStillOn(from: $0)
            }
        )
    }

    /// Everyone else who has not answered this round.
    ///
    /// You are excluded, deliberately. The first version listed the viewer among the people it
    /// had not heard from, directly above a button asking them — which reads as the app not
    /// knowing who it is talking to. Your own state is the button, or the tick that replaces it.
    var notYetSaidNames: [String] {
        namesFor(
            request.allParticipantIDs.filter {
                $0 != currentUserID && !request.hasCurrentStillOn(from: $0)
            }
        )
    }

    /// Whether to list who is in at all.
    ///
    /// Not until somebody has answered. Before that the list is every name on the plan under a
    /// heading saying nobody has replied, and it landed directly above `GroupStatusRow` saying
    /// "You and Sam are in" — two rows on one screen appearing to contradict each other, because
    /// one is about agreeing to the plan and the other about still coming to it. Once there is a
    /// real answer the distinction is obvious; before that it is just noise.
    var showsStillOnRoster: Bool {
        !request.stillOn.isEmpty
    }

    func sayStillOn() async {
        guard !isSending, let currentUserID else { return }
        isSending = true
        defer { isSending = false }

        do {
            request = try await requestService.sayStillOn(request, by: currentUserID)
        } catch {
            errorMessage = UserFacingError.message(for: error) ?? "Couldn't send that just now."
        }
    }

    /// You first, then the rest alphabetically — the same ordering as `GroupStatusRow`, so two
    /// lists on one screen do not disagree about where to look for yourself.
    private func namesFor(_ ids: [String]) -> [String] {
        let names = ids.map { id -> String in
            id == currentUserID ? "You" : (participantNames[id] ?? "Someone")
        }
        let you = names.filter { $0 == "You" }
        let others = names.filter { $0 != "You" }.sorted()
        return you + others
    }
}

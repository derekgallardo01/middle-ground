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

    /// Whether to offer the check-in at all.
    ///
    /// Only on a plan that has actually gone quiet. Offering it on a healthy plan is how a useful
    /// prompt becomes furniture people stop reading.
    var showsStillOn: Bool {
        guard let currentUserID else { return false }
        return momentum.wantsCheckIn && request.canSayStillOn(as: currentUserID)
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
        namesFor(request.allParticipantIDs.filter { request.hasCurrentStillOn(from: $0) })
    }

    /// And everyone who has not answered this round yet.
    var notYetSaidNames: [String] {
        namesFor(request.allParticipantIDs.filter { !request.hasCurrentStillOn(from: $0) })
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

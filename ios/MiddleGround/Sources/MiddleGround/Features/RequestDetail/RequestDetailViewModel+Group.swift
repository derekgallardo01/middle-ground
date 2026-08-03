import Foundation

/// Where a group plan stands, in names rather than IDs.
///
/// `attendeeIDs` and `awaitingResponseFrom` have always been computed on `Request` and shown in no
/// view. This turns them into something readable. Only for plans with more than two people: with
/// two, "waiting on them" is already the whole story and the existing waiting row says it.
extension RequestDetailViewModel {
    var showsGroupStatus: Bool {
        request.isGroupPlan && request.status != .cancelled && request.status != .declined
    }

    /// You first, then everyone else — the list is read to find yourself in it.
    var attendeeNames: [String] {
        ordered(request.attendeeIDs)
    }

    var awaitingNames: [String] {
        ordered(request.awaitingResponseFrom)
    }

    /// Nobody is owed an answer any more, so the row should not imply the plan is still forming.
    var groupIsSettled: Bool {
        !request.isOpen && request.status != .accepted
    }

    private func ordered(_ ids: [String]) -> [String] {
        let names = ids.map { id -> String in
            id == currentUserID ? "You" : (participantNames[id] ?? "Someone")
        }
        // "You" leads; the rest keep a stable alphabetical order so the line does not reshuffle
        // between reads.
        let you = names.filter { $0 == "You" }
        let others = names.filter { $0 != "You" }.sorted()
        return you + others
    }
}

import Foundation

/// Who has seen this plan.
///
/// Marked on opening the screen and again when a new message lands while it is open — not per
/// message and not per scroll. A receipt per line would be a write per reader per message, and
/// would put a tick beside every sentence, which is the part of messaging people actually dislike.
///
/// Shown as one quiet line under the transcript rather than against individual messages, for the
/// same reason.
extension RequestDetailViewModel {
    /// "Seen by Alex and Sam", or nothing at all.
    var seenBySentence: String? {
        let names = readReceipts
            .map { name(for: $0.userID) }
            .filter { $0 != "You" }
        guard !names.isEmpty else { return nil }
        return "Seen by \(names.formatted(.list(type: .and)))"
    }

    func observeReadReceipts() {
        guard let currentUserID else { return }
        readsTask.cancel()
        let requestID = request.id
        let repository = readReceiptRepository
        readsTask.task = Task { [weak self] in
            for await latest in repository.observeReceipts(
                forRequest: requestID,
                excluding: currentUserID
            ) {
                guard !Task.isCancelled else { return }
                await MainActor.run { self?.readReceipts = latest }
            }
        }
    }

    /// Records that this person has the plan open.
    ///
    /// Called on appear and whenever the transcript grows while they are still looking — the two
    /// moments where "seen" changes meaning. Not on every render, which would be a write per
    /// layout pass.
    func markRead() {
        guard let currentUserID else { return }
        let requestID = request.id
        let repository = readReceiptRepository
        Task { await repository.markRead(userID: currentUserID, forRequest: requestID) }
    }
}

import Foundation

/// Holds a cancellable task where a nonisolated `deinit` can reach it.
final class TaskBox: @unchecked Sendable {
    var task: Task<Void, Never>?
    func cancel() { task?.cancel() }
}

/// The conversation half of the plan screen.
///
/// Decisions live on the request document and messages live in `requests/{id}/messages` — see
/// `PlanMessage` for why the line falls there. This puts the two back together for display, since
/// the split is a storage concern and nobody reading the screen should be able to tell.
extension RequestDetailViewModel {
    /// Decisions and top-level messages, oldest first. Replies hang off their parent instead of
    /// appearing in the timeline, or a busy thread would bury the decision it is about.
    var transcript: [TranscriptEntry] {
        TranscriptEntry.transcript(
            decisions: request.negotiationChain,
            messages: messages
        )
    }

    func replies(to messageID: String) -> [PlanMessage] {
        TranscriptEntry.replies(to: messageID, in: messages)
    }

    /// A display name for anyone on the plan. Falls back rather than showing a raw ID.
    func name(for userID: String) -> String {
        if userID == currentUserID { return "You" }
        return participantNames[userID] ?? partnerName ?? "Someone"
    }

    /// The message the composer is currently aimed at, if any.
    var replyingTo: PlanMessage? {
        guard let replyingToID else { return nil }
        return messages.first { $0.id == replyingToID }
    }

    /// Streams the conversation for this plan.
    ///
    /// A listener rather than a fetch: a plan is argued over while people are both looking at it,
    /// and polling is how a conversation ends up a second behind the person typing into it.
    func observeMessages() {
        messagesTask.cancel()
        let requestID = request.id
        let repository = planMessages
        messagesTask.task = Task { [weak self] in
            for await latest in repository.observeMessages(forRequest: requestID, limit: 100) {
                guard !Task.isCancelled else { return }
                await MainActor.run { self?.messages = latest }
            }
        }
    }

    /// Removing your own line. Editing is deliberately absent — a transcript people arranged an
    /// evening around should not change under them afterwards.
    func deleteMessage(_ message: PlanMessage) async {
        guard message.senderID == currentUserID else { return }
        do {
            try await planMessages.delete(messageID: message.id, forRequest: request.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

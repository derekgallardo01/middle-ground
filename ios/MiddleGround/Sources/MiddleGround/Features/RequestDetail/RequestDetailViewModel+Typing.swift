import Foundation

/// Who is typing, and telling everyone else that you are.
///
/// The heartbeat is the whole design. A "started typing" event with a matching "stopped" is a
/// promise the client cannot keep — phones lose signal, get locked, and are force-quit
/// mid-sentence, and every one of those leaves an indicator on screen forever. Instead the flag
/// expires on its own after `TypingPresence.staleAfter` and is refreshed while typing continues,
/// so the worst a crash can do is stop saying something true.
extension RequestDetailViewModel {
    /// Names of everyone currently typing, excluding you.
    var typingNames: [String] {
        typing.map { name(for: $0.userID) }
    }

    func observeTyping() {
        guard let currentUserID else { return }
        typingTask.cancel()
        let requestID = request.id
        let repository = typingPresence
        typingTask.task = Task { [weak self] in
            for await latest in repository.observeTyping(
                forRequest: requestID,
                excluding: currentUserID
            ) {
                guard !Task.isCancelled else { return }
                await MainActor.run { self?.typing = latest }
            }
        }
    }

    /// Called as the composer's text changes.
    ///
    /// Refreshes at most once per `TypingPresence.heartbeat` rather than on every keystroke —
    /// otherwise a fast typist writes a document per character, which is precisely the cost that
    /// made typing indicators unaffordable before conversation moved off the request document.
    func noteTyping() {
        guard let currentUserID, !isCounterEmpty else { return }
        let now = Date()
        guard now.timeIntervalSince(lastTypingPing) >= TypingPresence.heartbeat else { return }
        lastTypingPing = now

        let requestID = request.id
        let repository = typingPresence
        Task { await repository.startTyping(userID: currentUserID, forRequest: requestID) }
    }

    /// Clears the flag at once, for the cases the client *can* be sure about: sending, and
    /// leaving the screen.
    func stopTyping() {
        guard let currentUserID else { return }
        lastTypingPing = .distantPast
        let requestID = request.id
        let repository = typingPresence
        Task { await repository.stopTyping(userID: currentUserID, forRequest: requestID) }
    }
}

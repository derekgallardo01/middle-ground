import Foundation

/// The composer: saying something, and proposing something.
///
/// The distinction this file exists to draw is the whole of it. **Plain text is a remark and
/// changes nothing. Attaching a time is an offer, and puts the decision back on everyone.**
///
/// Before `.comment` existed there was only the second kind. The send button's one path was
/// `.counter`, so asking "which entrance?" on a plan three people had agreed to withdrew the
/// agreement: the status fell back to `countered`, every acceptance was voided, and three people
/// who had said yes owed another answer. Nobody could ask a question without dismantling the plan
/// they were asking about, and it got worse the more people were on it.
///
/// Split out of `RequestDetailViewModel`, which was at the 500-line limit, exactly as the booking
/// code was. Stored properties stay on the class — Swift does not allow them in an extension.
extension RequestDetailViewModel {
    var isCounterEmpty: Bool {
        counterText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// A time on its own is a complete counter-proposal — "how about Sunday?" needs no prose.
    /// Text on its own is a comment, which needs words.
    var canSendCounter: Bool {
        counterProposedTime != nil ? true : !isCounterEmpty
    }

    /// Whether this person may say something, which is far more often than they may answer.
    var canComment: Bool {
        guard let currentUserID else { return false }
        return request.canMessage(as: currentUserID)
    }

    /// Whether what is being written will move the plan rather than just describe it.
    var isProposingNewTime: Bool { counterProposedTime != nil }

    /// One send button, three outcomes: a reply, a remark, or a proposal.
    ///
    /// Attaching a time is what makes it a proposal — the thing that moves the plan and puts the
    /// decision back on everyone. Plain text is conversation and changes nothing.
    func send() async {
        guard canSendCounter else { return }
        guard let time = counterProposedTime else {
            await sendMessage(replyingTo: replyingToID)
            return
        }
        // A counter with only a time still needs to read as something in the transcript.
        let message = isCounterEmpty ? Self.rescheduleText(for: time) : counterText
        await respond(with: .counter, text: message, newTime: time)
        counterProposedTime = nil
    }

    func saveForLater() async {
        await respond(with: .save)
    }

    /// Sends a line of conversation.
    ///
    /// Goes to `requests/{id}/messages` rather than onto the negotiation chain — see
    /// `PlanMessage`. One independent document per message, so two people sending at the same
    /// moment cannot overwrite each other, and a long conversation never grows the request
    /// document it belongs to.
    func sendMessage(replyingTo parentID: String? = nil) async {
        guard let currentUserID, !isCounterEmpty else { return }
        let text = counterText
        counterText = ""
        replyingToID = nil

        stopTyping()

        let message = PlanMessage(senderID: currentUserID, text: text, parentID: parentID)
        do {
            try await planMessages.send(message, forRequest: request.id)
            Haptics.shared.impact(.soft)
        } catch {
            // Put the text back rather than losing what somebody typed.
            counterText = text
            errorMessage = error.localizedDescription
        }
    }
}

import Foundation

/// Reporting content, and getting away from whoever sent it.
///
/// Required by App Review guideline 1.2: an app carrying user-generated content needs a way to
/// report it and a way to escape the person who sent it. Split into its own file for the same
/// reason as the booking, composer and message extensions — the view model sits at the 500-line
/// limit and every screen concern that can stand alone should.
extension RequestDetailViewModel {

    /// Everyone on the plan except you — the people a report could be about.
    ///
    /// Keyed off `currentUserID`, not `currentUser`. The view model already carries a comment
    /// explaining why: `currentUser` waits on a Firestore fetch of the display name, and for that
    /// half second the view believes it is nobody. The response row was fixed for this; the report
    /// control was not, so the one thing App Review guideline 1.2 requires was **missing from the
    /// toolbar** for the first moments of every plan opened on a slow connection.
    var reportableParticipants: [(id: String, name: String)] {
        guard let currentUserID else { return [] }
        return request.allParticipantIDs
            .filter { $0 != currentUserID }
            .map { (id: $0, name: participantNames[$0] ?? "Someone") }
            .sorted { $0.name < $1.name }
    }

    /// You cannot report your own request — there is nobody else to report.
    var canReport: Bool { !reportableParticipants.isEmpty }

    /// Opens the sheet with a subject already chosen when there is only one person it could be.
    ///
    /// With two people the question has one answer and asking it is noise. With three or more it
    /// is the whole point, and guessing is how a report lands on the wrong person.
    func beginReport() {
        // Cleared first. `Cancel` only dismisses the sheet, so a choice made and abandoned
        // survived — reopen it and somebody was already selected, with Submit enabled, chosen
        // during a different sitting. This function's own note says guessing is how a report
        // lands on the wrong person; a stale selection is a guess made by the last visit.
        reportedUserID = nil
        if reportableParticipants.count == 1 {
            reportedUserID = reportableParticipants[0].id
        }
        showReportSheet = true
    }

    // MARK: - Disagreeing about what happened

    /// Whether this plan is one the two of them remember differently.
    var canDispute: Bool {
        guard let currentUserID else { return false }
        return request.isDisputed && request.isParticipant(currentUserID) && !didRaiseDispute
    }

    /// Asks for a second look. Nothing about the plan changes — a contested plan already scores
    /// nothing either way, and that stays. This puts it in front of a person.
    func raiseDispute() async {
        guard let currentUserID, request.isDisputed else { return }
        isSending = true
        errorMessage = nil
        defer { isSending = false }

        let note = disputeNote.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await disputes.raise(
                PlanDispute(
                    raisedBy: currentUserID,
                    requestID: request.id,
                    planTitle: request.title,
                    note: note.isEmpty ? nil : note
                )
            )
            didRaiseDispute = true
            showDisputeSheet = false
            disputeNote = ""
            Haptics.shared.notification(.success)
        } catch {
            // Thrown rather than swallowed: somebody asking to be heard must be told if it did
            // not land, instead of believing it was filed.
            errorMessage = "Couldn't send that. Please try again."
            Haptics.shared.notification(.error)
        }
    }

    /// Files an abuse report (App Review guideline 1.2). Leaving the group is the other half
    /// and lives in Profile — reporting alone does not stop the person contacting you.
    func submitReport() async {
        guard let currentUser else {
            errorMessage = "Not signed in."
            return
        }
        guard let reportedUserID, reportableParticipants.contains(where: { $0.id == reportedUserID }) else {
            errorMessage = "Choose who this report is about."
            return
        }
        isSending = true
        errorMessage = nil
        defer { isSending = false }

        let note = reportNote.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await eventRepository.submitReport(
                ContentReport(
                    reporterID: currentUser.id,
                    requestID: request.id,
                    reportedUserID: reportedUserID,
                    reason: reportReason,
                    note: note.isEmpty ? nil : note
                )
            )
            await analytics.track(
                .contentReported,
                userID: currentUser.id,
                requestID: request.id,
                metadata: ["reason": reportReason.rawValue]
            )
            showReportSheet = false
            didSubmitReport = true
            reportNote = ""
            self.reportedUserID = nil
            Haptics.shared.notification(.success)
        } catch {
            errorMessage = "Couldn't send that report. Please try again."
            Haptics.shared.notification(.error)
        }
    }
}

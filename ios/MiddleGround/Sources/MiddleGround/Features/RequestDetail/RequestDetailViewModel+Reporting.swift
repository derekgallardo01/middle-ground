import Foundation

/// Reporting content, and getting away from whoever sent it.
///
/// Required by App Review guideline 1.2: an app carrying user-generated content needs a way to
/// report it and a way to escape the person who sent it. Split into its own file for the same
/// reason as the booking, composer and message extensions — the view model sits at the 500-line
/// limit and every screen concern that can stand alone should.
extension RequestDetailViewModel {

    /// Everyone on the plan except you — the people a report could be about.
    var reportableParticipants: [(id: String, name: String)] {
        guard let currentUser else { return [] }
        return request.allParticipantIDs
            .filter { $0 != currentUser.id }
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
        if reportableParticipants.count == 1 {
            reportedUserID = reportableParticipants[0].id
        }
        showReportSheet = true
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

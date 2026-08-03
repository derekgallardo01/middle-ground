import Foundation

/// Reporting content, and getting away from whoever sent it.
///
/// Required by App Review guideline 1.2: an app carrying user-generated content needs a way to
/// report it and a way to escape the person who sent it. Split into its own file for the same
/// reason as the booking, composer and message extensions — the view model sits at the 500-line
/// limit and every screen concern that can stand alone should.
extension RequestDetailViewModel {

    /// You cannot report your own request — there is nobody else to report.
    var canReport: Bool {
        guard let currentUser else { return false }
        return reportedUserID(from: currentUser.id) != nil
    }

    private func reportedUserID(from userID: String) -> String? {
        request.allParticipantIDs.first { $0 != userID }
    }

    /// Files an abuse report (App Review guideline 1.2). Leaving the group is the other half
    /// and lives in Profile — reporting alone does not stop the person contacting you.
    func submitReport() async {
        guard let currentUser, let reportedUserID = reportedUserID(from: currentUser.id) else {
            errorMessage = "Not signed in."
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
            Haptics.shared.notification(.success)
        } catch {
            errorMessage = "Couldn't send that report. Please try again."
            Haptics.shared.notification(.error)
        }
    }
}

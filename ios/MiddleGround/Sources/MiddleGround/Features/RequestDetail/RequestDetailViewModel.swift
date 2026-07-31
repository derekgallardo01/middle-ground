import Foundation
import Factory

@MainActor
@Observable
final class RequestDetailViewModel {
    private let requestService = Container.shared.requestService()
    private let authService = Container.shared.authService()
    private let gamificationService = Container.shared.gamificationService()
    private let userRepository = Container.shared.userRepository()
    private let eventRepository = Container.shared.eventRepository()
    private let analytics = Container.shared.analyticsService()

    var request: Request
    var currentUser: User?
    // Computed over private storage, not `didSet` — see the note in CreateRequestViewModel:
    // under @Observable a `didSet` that reassigns its own property recurses until the stack
    // overflows.
    private var counterTextStorage: String = ""
    var counterText: String {
        get { counterTextStorage }
        set { counterTextStorage = RequestLimits.clamp(newValue, to: RequestLimits.message) }
    }
    var isSending = false
    var errorMessage: String?
    var partnerName: String?
    var didCancel = false
    var showReschedulePicker = false
    var proposedNewTime = Date().addingTimeInterval(3600)

    /// Sends `.reschedule` with a new proposed time. Until now this response type had an
    /// emoji, label, XP rule, colour and status mapping — and no way to trigger it.
    func sendReschedule() async {
        guard let currentUser else {
            errorMessage = "Not signed in."
            return
        }
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            let previous = request
            var updated = request
            updated.proposedTime = proposedNewTime
            request = try await requestService.respond(
                to: updated,
                with: .reschedule,
                text: Self.rescheduleText(for: proposedNewTime),
                by: currentUser.id
            )
            showReschedulePicker = false
            await gamificationService.recordResponse(.reschedule, to: previous, for: currentUser.id)
            Haptics.shared.notification(.success)
        } catch {
            errorMessage = error.localizedDescription
            Haptics.shared.notification(.error)
        }
    }

    private static func rescheduleText(for date: Date) -> String {
        "How about \(date.formatted(date: .abbreviated, time: .shortened))?"
    }

    /// Who the viewer is, known on the first frame.
    ///
    /// Everything below only needs the ID, and `authService.currentUserID` has it in memory.
    /// Deriving these from `currentUser` meant waiting on a Firestore fetch of the display
    /// name first: for that half second the view believed it was nobody, so the response row
    /// was missing and every message in the chain rendered as the other person's — grey and
    /// left-aligned — before flipping sides once the name arrived.
    var currentUserID: String? { authService.currentUserID ?? currentUser?.id }

    /// Role-derived UI state. The creator waits; only the recipient answers.
    var canRespond: Bool {
        guard let currentUserID else { return false }
        return request.canRespond(as: currentUserID)
    }

    var isAwaitingResponse: Bool {
        guard let currentUserID else { return false }
        return request.isAwaitingResponse(for: currentUserID)
    }

    var canCancel: Bool {
        guard let currentUserID else { return false }
        return request.canCancel(as: currentUserID)
    }

    var waitingMessage: String {
        "Waiting for \(partnerName ?? "your partner") to respond"
    }

    init(request: Request) {
        self.request = request
        Task { await loadCurrentUser() }
    }

    func loadCurrentUser() async {
        currentUser = await authService.currentUser()
        await loadPartnerName()
    }

    /// Resolves the other participant's name so the waiting state can say who we're waiting on.
    private func loadPartnerName() async {
        guard let currentUser,
              let otherID = request.allParticipantIDs.first(where: { $0 != currentUser.id })
        else { return }
        partnerName = (try? await userRepository.user(id: otherID))?.name
    }

    /// Withdraws the request. Creator-only, enforced again in the service and the rules.
    func cancelRequest() async -> Bool {
        guard let currentUser else {
            errorMessage = "Not signed in."
            return false
        }
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            try await requestService.cancel(request, by: currentUser.id)
            didCancel = true
            Haptics.shared.notification(.success)
            return true
        } catch {
            errorMessage = error.localizedDescription
            Haptics.shared.notification(.error)
            return false
        }
    }

    var isCounterEmpty: Bool {
        counterText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func respond(with response: ResponseType, text: String? = nil) async {
        guard let currentUser else {
            errorMessage = "Not signed in."
            return
        }
        isSending = true
        errorMessage = nil
        do {
            let previous = request
            request = try await requestService.respond(to: request, with: response, text: text, by: currentUser.id)
            counterText = ""
            let outcome = await gamificationService.recordResponse(response, to: previous, for: currentUser.id)

            // The same action used to feel completely different depending on where you did
            // it: responding from the feed earned confetti and a haptic, responding from the
            // detail screen silently swapped a status badge. It awards the same XP either way,
            // so it should read the same either way.
            Haptics.shared.feedback(for: response)
            if let unlocked = outcome.newlyUnlocked.first {
                presentCelebration("Achievement unlocked: \(unlocked.title)")
            } else if response == .accept {
                presentCelebration("Request accepted! +\(outcome.xpAwarded) XP")
            } else if response == .negotiate {
                presentCelebration("Let's find a middle ground")
            }
        } catch {
            errorMessage = "Failed to send response."
            Haptics.shared.notification(.error)
        }
        isSending = false
    }

    var showCelebration = false
    var celebrationTitle = ""

    private func presentCelebration(_ title: String) {
        celebrationTitle = title
        showCelebration = true
    }

    func sendCounter() async {
        guard !isCounterEmpty else { return }
        await respond(with: .counter, text: counterText)
    }

    func saveForLater() async {
        await respond(with: .save)
    }

    // MARK: - Reporting

    var showReportSheet = false
    var reportReason: ReportReason = .harassment
    private var reportNoteStorage: String = ""
    var reportNote: String {
        get { reportNoteStorage }
        set { reportNoteStorage = RequestLimits.clamp(newValue, to: RequestLimits.reportNote) }
    }
    var didSubmitReport = false

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

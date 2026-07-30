import Foundation
import Factory

@MainActor
@Observable
final class RequestDetailViewModel {
    private let requestService = Container.shared.requestService()
    private let authService = Container.shared.authService()
    private let gamificationService = Container.shared.gamificationService()
    private let userRepository = Container.shared.userRepository()

    var request: Request
    var currentUser: User?
    var counterText: String = ""
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

    /// Role-derived UI state. The creator waits; only the recipient answers.
    var canRespond: Bool {
        guard let currentUser else { return false }
        return request.canRespond(as: currentUser.id)
    }

    var isAwaitingResponse: Bool {
        guard let currentUser else { return false }
        return request.isAwaitingResponse(for: currentUser.id)
    }

    var canCancel: Bool {
        guard let currentUser else { return false }
        return request.canCancel(as: currentUser.id)
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
            await gamificationService.recordResponse(response, to: previous, for: currentUser.id)
            Haptics.shared.notification(.success)
        } catch {
            errorMessage = "Failed to send response."
            Haptics.shared.notification(.error)
        }
        isSending = false
    }

    func sendCounter() async {
        guard !isCounterEmpty else { return }
        await respond(with: .counter, text: counterText)
    }

    func saveForLater() async {
        await respond(with: .save)
    }
}

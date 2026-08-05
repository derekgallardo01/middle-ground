import Foundation

/// Opening one plan up to somebody outside your groups.
///
/// Its own file for the same reason as the booking, composer, message, reporting and settlement
/// extensions: the view model sits at the 500-line limit, and every screen concern that can stand
/// alone should.
extension RequestDetailViewModel {
    // MARK: - Inviting someone to just this plan

    /// Whether this plan can be opened up to someone outside your groups.
    var canInviteToPlan: Bool {
        guard let currentUserID else { return false }
        return request.creatorID == currentUserID && request.isOpen
    }

    var planInviteCode: String? {
        request.planInviteCode.flatMap { $0.isEmpty ? nil : $0 }
    }

    func createPlanInvite() async {
        guard let currentUserID else { return }
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            request = try await requestService.createPlanInvite(for: request, by: currentUserID)
            Haptics.shared.impact(.light)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func revokePlanInvite() async {
        guard let currentUserID else { return }
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            request = try await requestService.revokePlanInvite(for: request, by: currentUserID)
            Haptics.shared.impact(.light)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

import Foundation
import Factory

@MainActor
@Observable
final class SpontaneousRequestViewModel {
    private let requestService = Container.shared.requestService()
    private let authService = Container.shared.authService()
    private let relationshipService = Container.shared.relationshipService()

    var currentUser: User?
    var relationships: [Relationship] = []
    /// relationship.id -> partner display name.
    var displayLabels: [String: String] = [:]

    /// True when the user has groups but nobody has joined any of them yet.
    var needsPartner: Bool {
        !relationships.isEmpty && relationships.allSatisfy { !$0.isPaired }
    }

    /// The code to share when nobody has joined yet, so the empty state can offer the share
    /// sheet inline instead of naming the Profile tab it cannot open.
    var inviteCode: String? {
        relationships.first { !$0.isPaired }?.inviteCode
    }

    func label(for relationship: Relationship) -> String {
        displayLabels[relationship.id] ?? relationship.type.displayName
    }

    /// Optional. A spontaneous plan is usually the quick idea itself, and forcing a title on
    /// somebody who just wants to ask "who's about?" is friction at exactly the wrong moment.
    /// `resolvedTitle` supplies a readable fallback so the feed never shows a blank row.
    var title: String = ""
    var details: String = ""

    /// How long the invite stays open — the thing that makes it spontaneous.
    ///
    /// This used to double as the plan's time: `proposedTime` was `now + expiresInMinutes`, so
    /// "expires in 30 minutes" and "happening in 30 minutes" were the same value and neither
    /// could be set independently. They are different questions.
    var expiresInMinutes: Int = 30

    /// When the thing actually happens. Off by default — "now-ish" is the spontaneous case.
    var hasEventTime: Bool = false
    var eventTime: Date = Date().addingTimeInterval(3_600)

    /// Everyone being asked, across every group. Was a single ID, which meant a spontaneous
    /// invite could only ever reach one person even when the point of it is "who's about?".
    var recipientIDs: Set<String> = []

    /// Also mint a plan-invite code, for somebody who is not on Middle Ground at all.
    ///
    /// Reuses the existing single-plan invite: they get this one plan, not the group and nothing
    /// after it. See `RequestService.createPlanInvite`.
    var invitesSomeoneOutside: Bool = false
    /// Set after sending, when `invitesSomeoneOutside` is on, so the view can offer the share sheet.
    private(set) var planInviteCode: String?

    /// What the feed will show. Never empty.
    var resolvedTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Something spontaneous?" : trimmed
    }

    /// Everyone the user could ask, across all their groups, de-duplicated.
    var everyone: [(id: String, name: String)] {
        guard let currentUserID = currentUser?.id else { return [] }
        var seen: Set<String> = []
        var people: [(id: String, name: String)] = []
        for relationship in relationships {
            for id in relationship.participantIDs where id != currentUserID && !seen.contains(id) {
                seen.insert(id)
                people.append((id, displayLabels[relationship.id] ?? relationship.type.displayName))
            }
        }
        return people
    }

    var isLoading = false
    var isLoadingPartners = false
    var errorMessage: String?

    /// Somebody has to be asked — in the app or outside it. The title is no longer part of this:
    /// it is optional, and `resolvedTitle` covers the empty case.
    var canSubmit: Bool {
        !recipientIDs.isEmpty || invitesSomeoneOutside
    }

    func loadCurrentUserAndPartners() async {
        isLoadingPartners = true
        currentUser = await authService.currentUser()
        if let userID = currentUser?.id {
            do {
                relationships = try await relationshipService.relationships(for: userID)
                displayLabels = await relationshipService.displayLabels(
                    for: relationships, currentUserID: userID
                )
                // Preselect the first person so the common case is one tap, without preventing
                // the user from adding more.
                if let firstPartner = relationships.compactMap({ $0.partnerID(excluding: userID) }).first {
                    recipientIDs = [firstPartner]
                }
            } catch {
                errorMessage = "Couldn't load partners."
            }
        }
        isLoadingPartners = false
    }

    func sendRequest() async -> Request? {
        guard canSubmit, let currentUser else { return nil }
        isLoading = true
        errorMessage = nil

        let request = Request(
            creatorID: currentUser.id,
            recipientIDs: Array(recipientIDs),
            category: .spontaneous,
            title: resolvedTitle,
            details: details.isEmpty ? nil : details,
            // The chosen time when there is one, otherwise the end of the window — which is the
            // old behaviour, and still the right default for "who's about in the next half hour?"
            proposedTime: hasEventTime
                ? eventTime
                : Date().addingTimeInterval(TimeInterval(expiresInMinutes * 60))
        )

        do {
            try await requestService.createRequest(request)
            if invitesSomeoneOutside {
                // Best effort: the plan is already sent, and failing to mint a code should not
                // report the whole thing as failed.
                let withInvite = try? await requestService.createPlanInvite(
                    for: request, by: currentUser.id
                )
                planInviteCode = withInvite?.planInviteCode
            }
            isLoading = false
            Haptics.shared.notification(.success)
            return request
        } catch {
            errorMessage = "Failed to send spontaneous request."
            isLoading = false
            Haptics.shared.notification(.error)
            return nil
        }
    }
}

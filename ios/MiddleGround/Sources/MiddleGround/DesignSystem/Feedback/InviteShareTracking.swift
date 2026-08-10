import Factory
import SwiftUI

/// Records that somebody shared an invite, wherever they shared it from.
///
/// `invite_shared` is the denominator of the pairing funnel
/// (`FirestoreAdminRepository.overview()`), and it was fired from **one of eight** share buttons —
/// not including the one on the last onboarding screen, which is where most people share for the
/// first time. So the funnel counted almost every successful pairing against almost no attempts,
/// and the conversion rate it reported was far too high with nothing to indicate it.
///
/// A modifier rather than a callback threaded through five view models: the event is the same
/// everywhere, and the only thing that differs is which group it was for. Anything that shares an
/// invite gets this and is counted.
///
/// `ShareLink` reports nothing back, so this is the *tap*, not a completed share — which is what
/// the event has always meant. `ProfileViewModel.noteInviteShared` says the same thing and this
/// keeps its wording.
struct InviteShareTracking: ViewModifier {
    /// Which group the code belongs to, when it is a group code. Plan invites pass nil and are
    /// distinguished by `kind`.
    let relationshipID: String?
    /// "group" or "plan" — the same vocabulary `RelationshipService.join` and
    /// `RequestService.createPlanInvite` already use.
    let kind: String

    private let analytics = Container.shared.analyticsService()
    private let auth = Container.shared.authService()

    func body(content: Content) -> some View {
        // `simultaneousGesture`, so the share sheet still opens. A plain `onTapGesture` swallows
        // the tap and the button stops working — the failure would be far louder than the one
        // this fixes, but it is worth saying why.
        content.simultaneousGesture(TapGesture().onEnded {
            guard let userID = auth.currentUserID else { return }
            Task {
                await analytics.track(
                    .inviteShared,
                    userID: userID,
                    relationshipID: relationshipID,
                    metadata: ["kind": kind]
                )
            }
        })
    }
}

extension View {
    /// Counts a tap on anything that shares an invite.
    func tracksInviteShare(relationshipID: String? = nil, kind: String = "group") -> some View {
        modifier(InviteShareTracking(relationshipID: relationshipID, kind: kind))
    }
}

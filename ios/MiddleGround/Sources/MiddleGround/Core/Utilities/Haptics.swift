import UIKit

final class Haptics {
    static let shared = Haptics()

    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let notification = UINotificationFeedbackGenerator()

    private init() {
        impactLight.prepare()
        impactMedium.prepare()
        notification.prepare()
    }

    func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        switch style {
        case .light: impactLight.impactOccurred()
        case .medium: impactMedium.impactOccurred()
        default: impactMedium.impactOccurred()
        }
    }

    func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        notification.notificationOccurred(type)
    }

    /// The single mapping from a response to how it should feel.
    ///
    /// Kept here rather than at each call site because the feed and the detail screen were
    /// choosing differently for the same action — and the feed fired one on tap while the view
    /// model fired another on completion, so accepting buzzed twice.
    func feedback(for response: ResponseType) {
        switch response {
        case .accept:
            notification(.success)
        case .decline:
            notification(.warning)
        case .negotiate, .counter, .reschedule:
            impact(.light)
        case .save:
            impact(.light)
        // Softer than an answer, because it is not one. A message that lands like an acceptance
        // makes speaking feel weightier than it is.
        case .comment:
            impact(.soft)
        }
    }
}

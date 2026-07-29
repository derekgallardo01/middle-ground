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
}

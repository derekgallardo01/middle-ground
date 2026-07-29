import SwiftUI

extension AnyTransition {
    static var requestPush: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .trailing).combined(with: .opacity)
        )
    }
    
    static var cardExpand: AnyTransition {
        .scale(scale: 0.95, anchor: .center)
            .combined(with: .opacity)
    }
}

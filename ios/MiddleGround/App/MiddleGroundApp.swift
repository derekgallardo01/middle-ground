import SwiftUI
import MiddleGround

@main
struct MiddleGroundApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            MiddleGroundRootView()
        }
    }
}

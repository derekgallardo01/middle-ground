import Foundation
import Factory

@MainActor
@Observable
final class AppState {
    private let authService = Container.shared.authService()
    
    var isOnboarded = false
    var currentUser: User?
    var selectedTab: Tab = .home
    var isCheckingAuth = true
    
    enum Tab {
        case home
        case calendar
        case activities
        case ai
        case profile
    }
    
    init() {
        Task {
            await checkAuthState()
        }
    }
    
    func checkAuthState() async {
        isCheckingAuth = true
        currentUser = await authService.currentUser()
        isOnboarded = currentUser != nil
        isCheckingAuth = false
    }
    
    func completeOnboarding(user: User) {
        currentUser = user
        isOnboarded = true
    }
    
    func signOut() async {
        try? await authService.signOut()
        currentUser = nil
        isOnboarded = false
    }
}

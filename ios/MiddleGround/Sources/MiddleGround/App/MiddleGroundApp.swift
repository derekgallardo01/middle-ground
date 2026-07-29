import SwiftUI

public struct MiddleGroundRootView: View {
    @State private var appState = AppState()
    
    public init() {}
    
    public var body: some View {
        Group {
            if appState.isCheckingAuth {
                splashScreen
            } else if appState.isOnboarded {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .environment(appState)
    }
    
    private var splashScreen: some View {
        ZStack {
            MGColors.sand.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "heart.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72)
                    .foregroundStyle(MGColors.coral)
                Text("Middle Ground")
                    .font(MGFonts.displayL)
            }
        }
    }
}

struct MainTabView: View {
    @Environment(AppState.self) private var appState
    
    var body: some View {
        @Bindable var appState = appState
        
        TabView(selection: $appState.selectedTab) {
            HomeView()
                .tabItem { Label("Requests", systemImage: "bubble.left.and.bubble.right") }
                .tag(AppState.Tab.home)
            
            CalendarView()
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag(AppState.Tab.calendar)
            
            GamificationView()
                .tabItem { Label("Activities", systemImage: "sparkles") }
                .tag(AppState.Tab.activities)
            
            AIAssistantView()
                .tabItem { Label("AI", systemImage: "cpu") }
                .tag(AppState.Tab.ai)
            
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person") }
                .tag(AppState.Tab.profile)
        }
        .tint(MGColors.indigo)
    }
}

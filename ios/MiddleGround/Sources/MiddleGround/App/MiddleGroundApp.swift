import SwiftUI

public struct MiddleGroundRootView: View {
    @State private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

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
        // An invite link. Parked on AppState rather than acted on here, because at this moment
        // we may not know who this is yet — see `pendingInviteCode`.
        .onOpenURL { url in
            guard let code = Relationship.inviteCode(fromLink: url) else { return }
            appState.pendingInviteCode = code
        }
        // Cloud Functions set the badge to the user's pending count; without this it would
        // never come back down, so the icon kept a number long after everything was answered.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await NotificationService.shared.clearBadge()
                await appState.trackAppOpened()
            }
        }
    }

    private var splashScreen: some View {
        ZStack {
            MGColors.sand.ignoresSafeArea()
            VStack(spacing: 16) {
                LogoMark()
                    .frame(width: 96, height: 96)
                Text("Middle Ground")
                    .mgFont(.displayL)
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

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person") }
                .tag(AppState.Tab.profile)

            // Present only for accounts carrying the server-issued `admin` claim. This is a
            // convenience gate: firestore.rules refuses the underlying reads regardless.
            if appState.isAdmin {
                AdminView()
                    .tabItem { Label("Admin", systemImage: "gauge.with.dots.needle.bottom.50percent") }
                    .tag(AppState.Tab.admin)
            }
        }
        .tint(MGColors.indigo)
    }
}

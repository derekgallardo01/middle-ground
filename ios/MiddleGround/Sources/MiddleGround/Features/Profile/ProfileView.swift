import SwiftUI

struct ProfileView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = ProfileViewModel()
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    profileHeader
                    settingsSection
                    aboutSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(MGColors.sand.ignoresSafeArea())
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
        }
    }
    
    private var profileHeader: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(MGColors.indigo.opacity(0.15))
                    .frame(width: 100, height: 100)
                Text(initials)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(MGColors.indigo)
            }
            
            VStack(spacing: 4) {
                Text(viewModel.user?.name ?? "Guest")
                    .font(MGFonts.h1)
                if !viewModel.levelDisplay.isEmpty {
                    Text(viewModel.levelDisplay)
                        .font(MGFonts.body)
                        .foregroundStyle(MGColors.warm600)
                }
            }
        }
        .padding(24)
        .background(MGColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: MGColors.slate.opacity(0.05), radius: 12, x: 0, y: 4)
    }
    
    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings")
                .font(MGFonts.h2)
            
            VStack(spacing: 0) {
                Toggle("Push Notifications", isOn: .init(
                    get: { viewModel.notificationsEnabled },
                    set: { _ in Task { await viewModel.toggleNotifications() } }
                ))
                .font(MGFonts.body)
                .padding()
                .background(MGColors.surface)
                
                Divider()
                    .padding(.leading)
                
                Button {
                    Task {
                        if await viewModel.signOut() {
                            await appState.checkAuthState()
                        }
                    }
                } label: {
                    HStack {
                        Text("Sign Out")
                            .font(MGFonts.body)
                            .foregroundStyle(MGColors.coral)
                        Spacer()
                        if viewModel.isLoading {
                            ProgressView()
                        }
                    }
                    .padding()
                    .background(MGColors.surface)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
    
    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About")
                .font(MGFonts.h2)
            
            VStack(spacing: 0) {
                SettingRow(title: "Help & Support", icon: "questionmark.circle")
                Divider().padding(.leading)
                SettingRow(title: "Privacy Policy", icon: "hand.raised")
                Divider().padding(.leading)
                SettingRow(title: "Terms of Service", icon: "doc.text")
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
    
    private var initials: String {
        guard let name = viewModel.user?.name else { return "?" }
        let components = name.split(separator: " ")
        let firstLetters = components.prefix(2).compactMap { $0.first }
        return String(firstLetters).uppercased()
    }
}

struct SettingRow: View {
    let title: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(MGColors.indigo)
                .frame(width: 24)
            Text(title)
                .font(MGFonts.body)
                .foregroundStyle(MGColors.slate)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MGColors.warm400)
        }
        .padding()
        .background(MGColors.surface)
    }
}

#Preview {
    AppConfiguration.useMockRepositories = true
    return ProfileView()
        .environment(AppState())
}

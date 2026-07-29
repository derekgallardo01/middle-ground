import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = OnboardingViewModel()
    
    var body: some View {
        ZStack {
            MGColors.sand.ignoresSafeArea()
            
            VStack(spacing: 0) {
                stepIndicator
                
                Spacer()
                
                Group {
                    switch viewModel.currentStep {
                    case .welcome:
                        welcomeStep
                    case .permissions:
                        permissionsStep
                    case .profile:
                        profileStep
                    case .relationship:
                        relationshipStep
                    case .done:
                        doneStep
                    }
                }
                .frame(maxHeight: .infinity)
                
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 60)
            .padding(.bottom, 40)
        }
        .alert("Oops", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
    
    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingViewModel.Step.allCases, id: \.self) { step in
                Capsule()
                    .fill(step == viewModel.currentStep ? MGColors.indigo : MGColors.warm200)
                    .frame(width: step == viewModel.currentStep ? 24 : 8, height: 8)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.currentStep)
            }
        }
    }
    
    private var welcomeStep: some View {
        VStack(spacing: 28) {
            ZStack {
                Circle()
                    .fill(MGColors.warm100)
                    .frame(width: 180, height: 180)
                
                Image(systemName: "heart.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72)
                    .foregroundStyle(MGColors.coral)
            }
            
            VStack(spacing: 12) {
                Text(viewModel.currentStep.title)
                    .font(MGFonts.displayL)
                    .multilineTextAlignment(.center)
                
                Text("Middle Ground helps people make decisions together — from date nights to dinner plans.")
                    .font(MGFonts.body)
                    .foregroundStyle(MGColors.warm600)
                    .multilineTextAlignment(.center)
            }
            
            PrimaryButton(title: "Continue with Apple", systemImage: "person.fill.checkmark") {
                viewModel.signInWithApple()
            }
            .disabled(viewModel.isLoading)
        }
    }
    
    private var permissionsStep: some View {
        VStack(spacing: 28) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 72))
                .foregroundStyle(MGColors.indigo)
            
            VStack(spacing: 12) {
                Text(viewModel.currentStep.title)
                    .font(MGFonts.displayL)
                    .multilineTextAlignment(.center)
                
                Text("Get notified when someone sends or responds to a request.")
                    .font(MGFonts.body)
                    .foregroundStyle(MGColors.warm600)
                    .multilineTextAlignment(.center)
            }
            
            PrimaryButton(title: "Enable Notifications") {
                viewModel.requestNotifications()
            }
            
            Button("Skip for now") {
                viewModel.advance()
            }
            .font(MGFonts.body)
            .foregroundStyle(MGColors.warm600)
        }
    }
    
    private var profileStep: some View {
        VStack(spacing: 28) {
            Text(viewModel.currentStep.title)
                .font(MGFonts.displayL)
                .multilineTextAlignment(.center)
            
            TextField("Your name", text: $viewModel.userName)
                .font(MGFonts.h2)
                .multilineTextAlignment(.center)
                .padding()
                .background(MGColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            
            PrimaryButton(title: "Continue") {
                viewModel.advance()
            }
            .disabled(!viewModel.canContinue)
        }
    }
    
    private var relationshipStep: some View {
        VStack(spacing: 28) {
            Text(viewModel.currentStep.title)
                .font(MGFonts.displayL)
                .multilineTextAlignment(.center)
            
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 12) {
                ForEach(RelationshipType.allCases) { type in
                    Button {
                        viewModel.selectedRelationshipType = type
                        Haptics.shared.impact(.light)
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: type.iconName)
                                .font(.system(size: 24))
                            Text(type.displayName)
                                .font(MGFonts.caption)
                        }
                        .foregroundStyle(viewModel.selectedRelationshipType == type ? .white : MGColors.slate)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(viewModel.selectedRelationshipType == type ? MGColors.indigo : MGColors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
            
            TextField("Partner/friend name (optional)", text: $viewModel.partnerName)
                .font(MGFonts.body)
                .padding()
                .background(MGColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            
            PrimaryButton(title: "Get Started") {
                Task {
                    if let user = await viewModel.completeOnboarding() {
                        appState.completeOnboarding(user: user)
                    }
                }
            }
            .disabled(!viewModel.canContinue || viewModel.isLoading)
        }
    }
    
    private var doneStep: some View {
        VStack(spacing: 28) {
            Text("🎉")
                .font(.system(size: 72))
            
            Text(viewModel.currentStep.title)
                .font(MGFonts.displayL)
                .multilineTextAlignment(.center)
            
            Text("Start by sending your first request.")
                .font(MGFonts.body)
                .foregroundStyle(MGColors.warm600)
                .multilineTextAlignment(.center)
        }
    }
}

#Preview {
    AppConfiguration.useMockRepositories = true
    return OnboardingView()
        .environment(AppState())
}

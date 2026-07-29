import Foundation
import Factory

@MainActor
@Observable
final class OnboardingViewModel {
    private let authService = Container.shared.authService()
    private let signInManager = Container.shared.signInWithAppleManager()
    private let userRepository = Container.shared.userRepository()
    private let relationshipRepository = Container.shared.relationshipRepository()
    private let notificationService = NotificationService.shared
    
    var currentStep: Step = .welcome
    var isLoading = false
    var errorMessage: String?
    
    var userName: String = ""
    var selectedRelationshipType: RelationshipType = .couple
    var partnerName: String = ""
    
    enum Step: CaseIterable {
        case welcome
        case permissions
        case profile
        case relationship
        case done
        
        var title: String {
            switch self {
            case .welcome: return "Meet in the Middle"
            case .permissions: return "Stay in sync"
            case .profile: return "What should we call you?"
            case .relationship: return "Who are you deciding with?"
            case .done: return "You're all set"
            }
        }
    }
    
    var canContinue: Bool {
        switch currentStep {
        case .welcome: return true
        case .permissions: return true
        case .profile: return !userName.trimmingCharacters(in: .whitespaces).isEmpty
        case .relationship: return partnerName.trimmingCharacters(in: .whitespaces).isEmpty == false
        case .done: return true
        }
    }
    
    func signInWithApple() {
        isLoading = true
        errorMessage = nil
        
        signInManager.signIn { [weak self] result in
            Task { @MainActor in
                self?.isLoading = false
                switch result {
                case .success(let appleResult):
                    do {
                        let user = try await self?.authService.signInWithApple(
                            idToken: appleResult.idToken,
                            nonce: appleResult.nonce,
                            fullName: appleResult.fullName
                        )
                        self?.userName = user?.name ?? ""
                        self?.advance()
                    } catch {
                        self?.errorMessage = error.localizedDescription
                    }
                case .failure(let error):
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    func requestNotifications() {
        Task {
            _ = await notificationService.requestAuthorization()
            advance()
        }
    }
    
    func completeOnboarding() async -> User? {
        isLoading = true
        errorMessage = nil
        
        do {
            guard var user = try await authService.currentUser() else {
                errorMessage = "Not signed in"
                isLoading = false
                return nil
            }
            
            let cleanName = userName.trimmingCharacters(in: .whitespaces)
            if !cleanName.isEmpty {
                user.name = cleanName
                try await userRepository.saveUser(user)
            }
            
            let relationship = Relationship(
                id: UUID().uuidString,
                participantIDs: [user.id],
                type: selectedRelationshipType
            )
            try await relationshipRepository.saveRelationship(relationship)
            
            isLoading = false
            advance()
            return user
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return nil
        }
    }
    
    func advance() {
        guard let currentIndex = Step.allCases.firstIndex(of: currentStep),
              currentIndex < Step.allCases.count - 1 else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            currentStep = Step.allCases[currentIndex + 1]
        }
    }
}

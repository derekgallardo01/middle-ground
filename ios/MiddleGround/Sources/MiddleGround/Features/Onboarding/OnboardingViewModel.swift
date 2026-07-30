import Foundation
import SwiftUI
import Factory

@MainActor
@Observable
final class OnboardingViewModel {
    private let authService = Container.shared.authService()
    private let signInManager = Container.shared.signInWithAppleManager()
    private let userRepository = Container.shared.userRepository()
    private let relationshipService = Container.shared.relationshipService()
    private let notificationService = NotificationService.shared

    var currentStep: Step = .welcome
    var isLoading = false
    var errorMessage: String?

    var userName: String = ""
    var selectedRelationshipType: RelationshipType = .couple
    var pairingMode: PairingMode = .create
    var inviteCodeInput: String = ""

    /// Set once onboarding creates a relationship, so the final step can show the code to share.
    private(set) var createdInviteCode: String?

    enum PairingMode: String, CaseIterable, Identifiable {
        case create
        case join

        var id: String { rawValue }

        var title: String {
            switch self {
            case .create: return "Invite someone"
            case .join: return "I have a code"
            }
        }
    }

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
        case .relationship:
            // Creating a group needs nothing extra; joining needs a plausible code.
            switch pairingMode {
            case .create: return true
            case .join: return Relationship.normalizeInviteCode(inviteCodeInput).count >= 6
            }
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
            guard var user = await authService.currentUser() else {
                errorMessage = "Not signed in"
                isLoading = false
                return nil
            }

            let cleanName = userName.trimmingCharacters(in: .whitespaces)
            if !cleanName.isEmpty {
                user.name = cleanName
                try await userRepository.saveUser(user)
            }

            switch pairingMode {
            case .create:
                let relationship = try await relationshipService.createRelationship(
                    type: selectedRelationshipType,
                    ownerID: user.id
                )
                createdInviteCode = relationship.inviteCode

            case .join:
                _ = try await relationshipService.join(inviteCode: inviteCodeInput, userID: user.id)
                createdInviteCode = nil
            }

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

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
    private let requestService = Container.shared.requestService()
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

    /// The signed-in user, held until the person dismisses the final step.
    ///
    /// Onboarding used to hand this straight to `AppState`, which flipped the root view to
    /// the main tabs immediately — so the "done" step (and the invite code on it) flashed
    /// past and was never actually readable.
    private(set) var completedUser: User?

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
            case .join:
                return Relationship.normalizeInviteCode(inviteCodeInput).count
                    == Relationship.inviteCodeLength
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
                        self?.errorMessage = UserFacingError.message(for: error)
                    }
                case .failure(let error):
                    self?.errorMessage = UserFacingError.message(for: error)
                }
            }
        }
    }

    #if DEBUG
    /// Debug-only sign-in used to drive multi-device pairing tests.
    func signInAsTestUser() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let user = try await authService.signInAsTestUser(named: Self.testerName())
                userName = user.name
                isLoading = false
                advance()
            } catch {
                errorMessage = UserFacingError.message(for: error)
                isLoading = false
            }
        }
    }

    /// Uses `-MGTestUser <label>` when supplied so a scripted two-device run is
    /// reproducible; falls back to a random name for ad-hoc manual testing.
    private static func testerName() -> String {
        if let label = AppConfiguration.testUserLabel, !label.isEmpty {
            return "Tester \(label)"
        }
        return "Tester \(Int.random(in: 100...999))"
    }
    #endif

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
                // A group code first, then a plan code — the same fallback Profile has always
                // had. The two codes look identical and nobody is told which they were handed,
                // so a plan code typed here used to fail with a raw error message while the very
                // same code worked one screen away.
                do {
                    _ = try await relationshipService.join(inviteCode: inviteCodeInput, userID: user.id)
                } catch {
                    try await requestService.joinPlan(inviteCode: inviteCodeInput, userID: user.id)
                }
                createdInviteCode = nil
            }

            isLoading = false
            completedUser = user
            advance()
            return user
        } catch {
            errorMessage = UserFacingError.message(for: error)
            isLoading = false
            return nil
        }
    }

    func advance() {
        guard let currentIndex = Step.allCases.firstIndex(of: currentStep),
              currentIndex < Step.allCases.count - 1 else { return }
        // No `withAnimation` here. A view model cannot reach `@Environment`, so motion started
        // from one can never honour Reduce Motion — the view animates this instead, by watching
        // `currentStep`.
        currentStep = Step.allCases[currentIndex + 1]
    }

    /// Whether there is a step to go back to.
    ///
    /// `.welcome` is the auth wall, so there is nothing behind it, and `.done` is a
    /// confirmation of work already committed — stepping back from either would be a lie.
    var canGoBack: Bool {
        guard let index = Step.allCases.firstIndex(of: currentStep) else { return false }
        return index > 0 && currentStep != .done
    }

    /// Steps backwards.
    ///
    /// There was no way back from any step: mistype your name on step 3, or pick the wrong
    /// relationship type on step 4, and the only remedy was deleting the app.
    func retreat() {
        guard canGoBack,
              let index = Step.allCases.firstIndex(of: currentStep) else { return }
        currentStep = Step.allCases[index - 1]
    }
}

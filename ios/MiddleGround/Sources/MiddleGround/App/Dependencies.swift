import Factory
import Foundation
import SwiftData

extension Container {
    var modelContainer: Factory<ModelContainer> {
        Factory(self) { LocalStore.shared.container }
    }

    var remoteRequestRepository: Factory<RequestRepository> {
        Factory(self) {
            AppConfiguration.useMockRepositories
                ? MockRequestRepository() as RequestRepository
                : FirestoreRequestRepository()
        }
    }

    var remoteUserRepository: Factory<UserRepository> {
        Factory(self) {
            AppConfiguration.useMockRepositories
                ? MockUserRepository() as UserRepository
                : FirestoreUserRepository()
        }
    }

    var remoteRelationshipRepository: Factory<RelationshipRepository> {
        Factory(self) {
            AppConfiguration.useMockRepositories
                ? MockRelationshipRepository() as RelationshipRepository
                : FirestoreRelationshipRepository()
        }
    }

    var requestRepository: Factory<RequestRepository> {
        Factory(self) {
            CachedRequestRepository(
                remote: self.remoteRequestRepository(),
                modelContainer: self.modelContainer()
            )
        }
    }

    var userRepository: Factory<UserRepository> {
        Factory(self) {
            CachedUserRepository(
                remote: self.remoteUserRepository(),
                modelContainer: self.modelContainer()
            )
        }
    }

    var relationshipRepository: Factory<RelationshipRepository> {
        Factory(self) {
            CachedRelationshipRepository(
                remote: self.remoteRelationshipRepository(),
                modelContainer: self.modelContainer()
            )
        }
    }

    var requestService: Factory<RequestService> {
        Factory(self) {
            RequestService(repository: self.requestRepository())
        }
    }

    var relationshipService: Factory<RelationshipService> {
        Factory(self) {
            RelationshipService(
                repository: self.relationshipRepository(),
                userRepository: self.userRepository()
            )
        }
    }

    var eventRepository: Factory<EventRepository> {
        Factory(self) {
            #if DEBUG
            if AppConfiguration.useMockRepositories {
                return MockEventRepository()
            }
            #endif
            return FirestoreEventRepository()
        }
    }

    var analyticsService: Factory<AnalyticsService> {
        Factory(self) { AnalyticsService(repository: self.eventRepository()) }
    }

    var gamificationRepository: Factory<GamificationRepository> {
        Factory(self) {
            #if DEBUG
            if AppConfiguration.useMockRepositories {
                return MockGamificationRepository()
            }
            #endif
            return FirestoreGamificationRepository()
        }
    }

    var adminRepository: Factory<AdminRepository> {
        Factory(self) {
            #if DEBUG
            if AppConfiguration.useMockRepositories {
                return MockAdminRepository()
            }
            #endif
            return FirestoreAdminRepository()
        }
    }

    var authService: Factory<AuthServiceProtocol> {
        Factory(self) {
            #if DEBUG
            if AppConfiguration.useMockRepositories {
                return PreviewAuthService()
            }
            #endif
            return AuthService()
        }
    }

    var sharedLocationRepository: Factory<SharedLocationRepository> {
        Factory(self) {
            #if DEBUG
            if AppConfiguration.useMockRepositories {
                return MockSharedLocationRepository()
            }
            #endif
            return FirestoreSharedLocationRepository()
        }
    }

    /// Mocked in previews and UI tests so nothing depends on where the host machine is.
    var locationService: Factory<LocationProviding> {
        Factory(self) {
            AppConfiguration.useMockRepositories
                ? MockLocationService() as LocationProviding
                : LocationService()
        }
    }

    var notificationSettingsRepository: Factory<NotificationSettingsRepository> {
        Factory(self) {
            #if DEBUG
            if AppConfiguration.useMockRepositories {
                return MockNotificationSettingsRepository()
            }
            #endif
            return FirestoreNotificationSettingsRepository()
        }
    }

    var gamificationService: Factory<GamificationServiceProtocol> {
        Factory(self) {
            AppConfiguration.useMockRepositories
                ? MockGamificationService() as GamificationServiceProtocol
                : GamificationService(mirror: self.gamificationRepository())
        }
    }

    /// Mocked in previews and UI tests so a clash never depends on the host machine's calendar.
    var calendarConflictService: Factory<CalendarConflictChecking> {
        Factory(self) {
            AppConfiguration.useMockRepositories
                ? MockCalendarConflictService() as CalendarConflictChecking
                : CalendarConflictService()
        }
    }

    var signInWithAppleManager: Factory<SignInWithAppleManager> {
        // Only ever resolved from @MainActor view models; the manager drives UIKit presentation.
        Factory(self) { MainActor.assumeIsolated { SignInWithAppleManager() } }
    }
}

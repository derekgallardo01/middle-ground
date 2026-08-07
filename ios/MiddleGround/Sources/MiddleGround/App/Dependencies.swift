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

    var availabilityRepository: Factory<AvailabilityRepository> {
        Factory(self) {
            #if DEBUG
            if AppConfiguration.useMockRepositories {
                return MockAvailabilityRepository()
            }
            #endif
            return FirestoreAvailabilityRepository()
        }
    }

    var planReadReceiptRepository: Factory<PlanReadReceiptRepository> {
        Factory(self) {
            #if DEBUG
            if AppConfiguration.useMockRepositories {
                return MockPlanReadReceiptRepository()
            }
            #endif
            return FirestorePlanReadReceiptRepository()
        }
    }

    var typingPresenceRepository: Factory<TypingPresenceRepository> {
        Factory(self) {
            #if DEBUG
            if AppConfiguration.useMockRepositories {
                return MockTypingPresenceRepository()
            }
            #endif
            return FirestoreTypingPresenceRepository()
        }
    }

    var planMessageRepository: Factory<PlanMessageRepository> {
        Factory(self) {
            #if DEBUG
            if AppConfiguration.useMockRepositories {
                return MockPlanMessageRepository()
            }
            #endif
            return FirestorePlanMessageRepository()
        }
    }

    var disputeRepository: Factory<DisputeRepository> {
        Factory(self) {
            #if DEBUG
            if AppConfiguration.useMockRepositories {
                return MockDisputeRepository()
            }
            #endif
            return FirestoreDisputeRepository()
        }
    }

    var planOutcomeRepository: Factory<PlanOutcomeRepository> {
        Factory(self) {
            #if DEBUG
            if AppConfiguration.useMockRepositories {
                return MockPlanOutcomeRepository()
            }
            #endif
            return FirestorePlanOutcomeRepository()
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

    var venueRepository: Factory<VenueRepository> {
        Factory(self) {
            #if DEBUG
            if AppConfiguration.useMockRepositories {
                return MockVenueRepository()
            }
            #endif
            return FirestoreVenueRepository()
        }
    }

    /// The one line a booking partnership changes. Everything above this reads the protocol, so
    /// swapping the implementation is the whole integration — see `ReservationProvider`.
    /// Places near you, found on the device.
    ///
    /// Registered beside the reservation provider so the two moments stay separate: this one is
    /// before a plan exists, that one is after. Swapping in Google Places later is a change here
    /// and nowhere else.
    var placeDiscoveryProvider: Factory<PlaceDiscoveryProvider> {
        Factory(self) {
            AppConfiguration.useMockRepositories
                ? MockPlaceDiscoveryProvider() as PlaceDiscoveryProvider
                : MapKitPlaceDiscoveryProvider()
        }
    }

    /// Pictures of the places discovery found. Apple's own imagery in both tiers, so this stays a
    /// keyless feature — see `PlaceImageProvider` for why a photo API was not worth the trade.
    var placeImageProvider: Factory<PlaceImageProviding> {
        Factory(self) {
            AppConfiguration.useMockRepositories
                ? MockPlaceImageProvider() as PlaceImageProviding
                : MapKitPlaceImageProvider()
        }
    }

    var reservationProvider: Factory<ReservationProvider> {
        Factory(self) { CuratedVenueReservationProvider(venues: self.venueRepository()) }
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

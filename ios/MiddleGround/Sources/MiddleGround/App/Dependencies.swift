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
                ? MockRequestRepository()
                : FirestoreRequestRepository()
        }
    }
    
    var remoteUserRepository: Factory<UserRepository> {
        Factory(self) {
            AppConfiguration.useMockRepositories
                ? MockUserRepository()
                : FirestoreUserRepository()
        }
    }
    
    var remoteRelationshipRepository: Factory<RelationshipRepository> {
        Factory(self) {
            AppConfiguration.useMockRepositories
                ? MockRelationshipRepository()
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
    
    var syncService: Factory<SyncService> {
        Factory(self) {
            SyncService(
                requestRepository: self.requestRepository(),
                userRepository: self.userRepository(),
                relationshipRepository: self.relationshipRepository()
            )
        }
    }
    
    var authService: Factory<AuthServiceProtocol> {
        Factory(self) { AuthService() }
    }
    
    var gamificationService: Factory<GamificationServiceProtocol> {
        Factory(self) {
            AppConfiguration.useMockRepositories
                ? MockGamificationService()
                : GamificationService()
        }
    }
    
    var signInWithAppleManager: Factory<SignInWithAppleManager> {
        Factory(self) { SignInWithAppleManager() }
    }
}

import Foundation
import SwiftData

@MainActor
final class LocalStore {
    static let shared = LocalStore()
    
    let container: ModelContainer
    
    private init() {
        let schema = Schema([
            RequestEntity.self,
            UserEntity.self,
            RelationshipEntity.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to initialize SwiftData container: \(error.localizedDescription)")
        }
    }
    
    var context: ModelContext {
        ModelContext(container)
    }
}

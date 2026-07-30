import Foundation
import SwiftData

/// Owns the on-disk SwiftData container backing the offline cache.
final class LocalStore {
    static let shared = LocalStore()

    let container: ModelContainer

    /// True when the on-disk store could not be opened and we fell back to memory.
    /// Callers can surface this to explain why nothing persists across launches.
    let isEphemeral: Bool

    private static let schema = Schema([
        RequestEntity.self,
        UserEntity.self,
        RelationshipEntity.self
    ])

    private init() {
        // A failure here used to be `fatalError`, which turned any migration problem on
        // upgrade into an unrecoverable launch crash. The cache is derived data — Firestore
        // is the source of truth — so degrading to an in-memory store is always better than
        // refusing to start.
        if let onDisk = try? ModelContainer(
            for: Self.schema,
            configurations: [ModelConfiguration(schema: Self.schema, isStoredInMemoryOnly: false)]
        ) {
            container = onDisk
            isEphemeral = false
            return
        }

        if let inMemory = try? ModelContainer(
            for: Self.schema,
            configurations: [ModelConfiguration(schema: Self.schema, isStoredInMemoryOnly: true)]
        ) {
            MGLog.storage.error("On-disk store unavailable — running with an in-memory cache. Offline data will not persist.")
            container = inMemory
            isEphemeral = true
            return
        }

        // An in-memory container cannot realistically fail; if it does the schema itself is
        // invalid, which is a programmer error rather than a runtime condition.
        preconditionFailure("LocalStore: schema is invalid — neither an on-disk nor an in-memory container could be created.")
    }

    var context: ModelContext {
        ModelContext(container)
    }
}

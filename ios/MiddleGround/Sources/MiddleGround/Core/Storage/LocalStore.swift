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

    /// Explicit store location, with the parent directory created up front.
    ///
    /// SwiftData defaults to `Application Support/default.store`, but that directory does not
    /// exist in a fresh app container and SwiftData does not create it — the store then fails
    /// with "Sandbox access to file-write-create denied" and the cache silently degrades to
    /// memory. Observed on a clean simulator install.
    private static func makeStoreURL() -> URL? {
        let fileManager = FileManager.default
        guard let appSupport = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }

        if !fileManager.fileExists(atPath: appSupport.path) {
            try? fileManager.createDirectory(at: appSupport, withIntermediateDirectories: true)
        }
        return appSupport.appending(path: "MiddleGround.store")
    }

    private init() {
        // Mock mode is in-memory, always.
        //
        // Mock mode exists to give a deterministic app with no backend, and an on-disk cache
        // quietly broke that: a response given in one launch was still there in the next, so
        // "the fixtures" drifted with use. It surfaced as UI tests that passed alone and failed
        // in sequence — the earlier test had accepted the plan a later one needed unanswered —
        // and it affects screenshots and demos the same way, just less visibly.
        if AppConfiguration.useMockRepositories,
           let ephemeral = try? ModelContainer(
               for: Self.schema,
               configurations: [ModelConfiguration(schema: Self.schema, isStoredInMemoryOnly: true)]
           ) {
            container = ephemeral
            isEphemeral = true
            return
        }

        // A failure here used to be `fatalError`, which turned any migration problem on
        // upgrade into an unrecoverable launch crash. The cache is derived data — Firestore
        // is the source of truth — so degrading to an in-memory store is always better than
        // refusing to start.
        if let url = Self.makeStoreURL(),
           let onDisk = try? ModelContainer(
               for: Self.schema,
               configurations: [ModelConfiguration(schema: Self.schema, url: url)]
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

    /// Deletes every cached row.
    ///
    /// Called on sign-out: the cache is derived data keyed by whoever was signed in, and
    /// leaving it behind meant the next account on the same device could see the previous
    /// user's requests before the remote merge replaced them.
    func purgeAll() {
        let ctx = context
        do {
            try ctx.delete(model: RequestEntity.self)
            try ctx.delete(model: UserEntity.self)
            try ctx.delete(model: RelationshipEntity.self)
            try ctx.save()
        } catch {
            MGLog.storage.error("Failed to purge local cache on sign-out: \(error.localizedDescription, privacy: .public)")
        }
    }
}

import Foundation

/// Points shared for one plan.
///
/// A subcollection under the request rather than a field on it: the client rewrites the whole
/// request document when it responds, so a field would be dropped by any client that predates it,
/// and the security rules would have to police location inside the same branch that polices
/// negotiation. Separate documents keep the two concerns apart and let a point be deleted on its
/// own.
protocol SharedLocationRepository: Sendable {
    func locations(forRequest requestID: String) async throws -> [SharedLocation]
    func share(_ location: SharedLocation, forRequest requestID: String) async throws
    func stopSharing(userID: String, forRequest requestID: String) async throws
}

actor MockSharedLocationRepository: SharedLocationRepository {
    private var storage: [String: [SharedLocation]] = [:]

    func locations(forRequest requestID: String) async throws -> [SharedLocation] {
        storage[requestID] ?? []
    }

    func share(_ location: SharedLocation, forRequest requestID: String) async throws {
        var existing = storage[requestID] ?? []
        existing.removeAll { $0.userID == location.userID }
        existing.append(location)
        storage[requestID] = existing
    }

    func stopSharing(userID: String, forRequest requestID: String) async throws {
        storage[requestID]?.removeAll { $0.userID == userID }
    }
}

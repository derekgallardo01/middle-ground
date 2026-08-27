import Foundation
import SwiftData

@Model
final class RequestEntity {
    @Attribute(.unique) var id: String
    var creatorID: String
    var recipientIDs: [String]
    var categoryRaw: String
    var title: String
    var details: String?
    var proposedTime: Date?
    /// Optional and appended, so SwiftData migrates existing stores on its own. Persisted because
    /// this repository is remote-then-local: a field the entity does not carry is invisible to the
    /// whole app even when the network fetch worked. That is how `name` was lost, and `seats`
    /// after it.
    var endTime: Date?
    /// The zone the plan happens in. Lost here, and a trip abroad silently reads in the
    /// reader's zone the moment the app is opened offline.
    var timeZoneID: String?
    var location: String?
    /// The plan's face. Lost here, and every card in a cold-launched offline feed falls back to
    /// the category — which is the flat, identical-hearts feed this field exists to end.
    var emoji: String?
    var statusRaw: String
    var negotiationChainData: Data?
    /// Optional so SwiftData stores created before attendance existed still load.
    var confirmationsData: Data?
    /// Optional, and appended, so SwiftData migrates existing stores on its own.
    ///
    /// This repository is remote-then-local — `fetchLocal` is what the app actually reads — so a
    /// field that is not persisted here is invisible everywhere even when the network fetch
    /// succeeded. That is how a group lost its name (`9ff2d97`), and `seats` is still losing that
    /// way today.
    var stillOnData: Data?
    var cancellationReasonRaw: String?
    var stakeData: Data?
    var planInviteCode: String?
    var planInviteSeats: Int?
    var createdAt: Date
    var updatedAt: Date
    var needsSync: Bool

    init(from request: Request) {
        self.id = request.id
        self.creatorID = request.creatorID
        self.recipientIDs = request.recipientIDs
        self.categoryRaw = request.category.rawValue
        self.title = request.title
        self.details = request.details
        self.proposedTime = request.proposedTime
        self.endTime = request.endTime
        self.timeZoneID = request.timeZoneID
        self.location = request.location
        self.emoji = request.emoji
        self.statusRaw = request.status.rawValue
        self.createdAt = request.createdAt
        self.updatedAt = request.updatedAt
        self.needsSync = false
        self.negotiationChainData = try? JSONEncoder().encode(request.negotiationChain)
        self.confirmationsData = try? JSONEncoder().encode(request.confirmations)
        self.stillOnData = try? JSONEncoder().encode(request.stillOn)
        self.cancellationReasonRaw = request.cancellationReason?.rawValue
        self.stakeData = request.stake.flatMap { try? JSONEncoder().encode($0) }
        self.planInviteCode = request.planInviteCode
        self.planInviteSeats = request.planInviteSeats
    }

    func update(from request: Request) {
        self.creatorID = request.creatorID
        self.recipientIDs = request.recipientIDs
        self.categoryRaw = request.category.rawValue
        self.title = request.title
        self.details = request.details
        self.proposedTime = request.proposedTime
        self.endTime = request.endTime
        self.timeZoneID = request.timeZoneID
        self.location = request.location
        self.emoji = request.emoji
        self.statusRaw = request.status.rawValue
        self.createdAt = request.createdAt
        self.updatedAt = request.updatedAt
        self.negotiationChainData = try? JSONEncoder().encode(request.negotiationChain)
        self.confirmationsData = try? JSONEncoder().encode(request.confirmations)
        self.stillOnData = try? JSONEncoder().encode(request.stillOn)
        self.cancellationReasonRaw = request.cancellationReason?.rawValue
        self.stakeData = request.stake.flatMap { try? JSONEncoder().encode($0) }
        self.planInviteCode = request.planInviteCode
        self.planInviteSeats = request.planInviteSeats
    }

    func toModel() -> Request? {
        // Same fallback as the Firestore DTO: an unrecognised category must not make a cached
        // request disappear. Without this the offline cache would drop exactly the requests the
        // network path now keeps.
        let category = RequestCategory(storedValue: categoryRaw)
        guard let status = RequestStatus(rawValue: statusRaw) else {
            return nil
        }

        let negotiationChain: [NegotiationMessage]
        if let data = negotiationChainData {
            negotiationChain = (try? JSONDecoder().decode([NegotiationMessage].self, from: data)) ?? []
        } else {
            negotiationChain = []
        }

        let confirmations: [String: ConfirmationOutcome]
        if let data = confirmationsData {
            confirmations = (try? JSONDecoder().decode(
                [String: ConfirmationOutcome].self, from: data
            )) ?? [:]
        } else {
            confirmations = [:]
        }

        let stillOn: [String: Date]
        if let data = stillOnData {
            stillOn = (try? JSONDecoder().decode([String: Date].self, from: data)) ?? [:]
        } else {
            stillOn = [:]
        }

        return Request(
            id: id,
            creatorID: creatorID,
            recipientIDs: recipientIDs,
            category: category,
            title: title,
            details: details,
            proposedTime: proposedTime,
            endTime: endTime,
            timeZoneID: timeZoneID,
            location: location,
            emoji: emoji,
            status: status,
            negotiationChain: negotiationChain,
            confirmations: confirmations,
            stillOn: stillOn,
            cancellationReason: cancellationReasonRaw.flatMap(CancellationReason.init(rawValue:)),
            stake: stakeData.flatMap { try? JSONDecoder().decode(Stake.self, from: $0) },
            planInviteCode: planInviteCode,
            planInviteSeats: planInviteSeats,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

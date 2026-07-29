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
    var location: String?
    var statusRaw: String
    var negotiationChainData: Data?
    var savedForLater: Bool
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
        self.location = request.location
        self.statusRaw = request.status.rawValue
        self.savedForLater = request.savedForLater
        self.createdAt = request.createdAt
        self.updatedAt = request.updatedAt
        self.needsSync = false
        self.negotiationChainData = try? JSONEncoder().encode(request.negotiationChain)
    }
    
    func update(from request: Request) {
        self.creatorID = request.creatorID
        self.recipientIDs = request.recipientIDs
        self.categoryRaw = request.category.rawValue
        self.title = request.title
        self.details = request.details
        self.proposedTime = request.proposedTime
        self.location = request.location
        self.statusRaw = request.status.rawValue
        self.savedForLater = request.savedForLater
        self.createdAt = request.createdAt
        self.updatedAt = request.updatedAt
        self.negotiationChainData = try? JSONEncoder().encode(request.negotiationChain)
    }
    
    func toModel() -> Request? {
        guard let category = RequestCategory(rawValue: categoryRaw),
              let status = RequestStatus(rawValue: statusRaw) else {
            return nil
        }
        
        let negotiationChain: [NegotiationMessage]
        if let data = negotiationChainData {
            negotiationChain = (try? JSONDecoder().decode([NegotiationMessage].self, from: data)) ?? []
        } else {
            negotiationChain = []
        }
        
        return Request(
            id: id,
            creatorID: creatorID,
            recipientIDs: recipientIDs,
            category: category,
            title: title,
            details: details,
            proposedTime: proposedTime,
            location: location,
            status: status,
            negotiationChain: negotiationChain,
            savedForLater: savedForLater,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

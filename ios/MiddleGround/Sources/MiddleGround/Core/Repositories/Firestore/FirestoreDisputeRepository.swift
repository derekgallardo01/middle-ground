import FirebaseFirestore
import Foundation

actor FirestoreDisputeRepository: DisputeRepository {
    /// Computed, not stored: constructing this type must not require FirebaseApp.configure().
    private var db: Firestore { Firestore.firestore() }
    private static let collection = "disputes"

    func raise(_ dispute: PlanDispute) async throws {
        try db.collection(Self.collection)
            .document(dispute.id)
            .setData(from: DisputeDTO(from: dispute))
    }

    func recentDisputes(limit: Int) async throws -> [PlanDispute] {
        let snapshot = try await db.collection(Self.collection)
            .order(by: "at", descending: true)
            .limit(to: limit)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: DisputeDTO.self).toModel() }
    }

    /// Writes only the three resolution fields.
    ///
    /// The rules refuse anything else, and should: what somebody said happened is the thing being
    /// reviewed, so it has to read exactly as filed. A whole-document write would be rejected.
    func resolveDispute(id: String, as resolution: ReportResolution, by adminID: String) async throws {
        try await db.collection(Self.collection)
            .document(id)
            .updateData([
                "resolution": resolution.rawValue,
                "resolvedBy": adminID,
                "resolvedAt": Timestamp(date: Date())
            ])
    }
}

// MARK: - DTO

private struct DisputeDTO: Codable {
    @DocumentID var id: String?
    var raisedBy: String
    var requestID: String
    var planTitle: String
    var note: String?
    var at: Timestamp
    var resolution: String?
    var resolvedBy: String?
    var resolvedAt: Timestamp?

    init(from dispute: PlanDispute) {
        self.id = dispute.id
        self.raisedBy = dispute.raisedBy
        self.requestID = dispute.requestID
        self.planTitle = dispute.planTitle
        self.note = dispute.note
        self.at = Timestamp(date: dispute.at)
        self.resolution = dispute.resolution?.rawValue
        self.resolvedBy = dispute.resolvedBy
        self.resolvedAt = dispute.resolvedAt.map { Timestamp(date: $0) }
    }

    func toModel() -> PlanDispute? {
        guard let id else { return nil }
        return PlanDispute(
            id: id,
            raisedBy: raisedBy,
            requestID: requestID,
            planTitle: planTitle,
            note: note,
            at: at.dateValue(),
            resolution: resolution.flatMap(ReportResolution.init(rawValue:)),
            resolvedBy: resolvedBy,
            resolvedAt: resolvedAt?.dateValue()
        )
    }
}

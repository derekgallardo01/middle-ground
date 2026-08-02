import FirebaseAuth
import FirebaseFirestore
import Foundation

actor FirestorePlanOutcomeRepository: PlanOutcomeRepository {
    /// Computed, not stored: constructing this type must not require FirebaseApp.configure().
    private var db: Firestore { Firestore.firestore() }
    private static let collection = "plan_outcomes"
    private static let intentCollection = "booking_intents"

    func record(_ outcome: PlanOutcome) async {
        // Swallows failures, like the event repository. A missing row skews a rate slightly; a
        // thrown error would roll back somebody's cancellation, which is far worse.
        guard Auth.auth().currentUser != nil else { return }
        do {
            try db.collection(Self.collection)
                .document(UUID().uuidString)
                .setData(from: PlanOutcomeDTO(from: outcome))
        } catch {
            MGLog.storage.error("Plan outcome not recorded: \(error.localizedDescription, privacy: .public)")
        }
    }

    func recordBookingIntent(_ intent: BookingIntent) async {
        guard Auth.auth().currentUser != nil else { return }
        do {
            try db.collection(Self.intentCollection)
                .document(UUID().uuidString)
                .setData(from: BookingIntentDTO(from: intent))
        } catch {
            MGLog.storage.error("Booking intent not recorded: \(error.localizedDescription, privacy: .public)")
        }
    }

    func recentOutcomes(limit: Int) async throws -> [PlanOutcome] {
        let snapshot = try await db.collection(Self.collection)
            .order(by: "at", descending: true)
            .limit(to: limit)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: PlanOutcomeDTO.self).toModel() }
    }
}

// MARK: - DTO

private struct BookingIntentDTO: Codable {
    var provider: String
    var groupSize: Int
    var category: String
    var hoursBeforePlan: Int?
    var at: Timestamp

    init(from intent: BookingIntent) {
        self.provider = intent.provider
        self.groupSize = intent.groupSize
        self.category = intent.category.rawValue
        self.hoursBeforePlan = intent.hoursBeforePlan
        self.at = Timestamp(date: intent.at)
    }
}

private struct PlanOutcomeDTO: Codable {
    var outcome: String
    var groupSize: Int
    var category: String
    var hadProposedTime: Bool
    var hoursBeforePlan: Int?
    var at: Timestamp

    init(from outcome: PlanOutcome) {
        self.outcome = outcome.outcome.rawValue
        self.groupSize = outcome.groupSize
        self.category = outcome.category.rawValue
        self.hadProposedTime = outcome.hadProposedTime
        self.hoursBeforePlan = outcome.hoursBeforePlan
        self.at = Timestamp(date: outcome.at)
    }

    func toModel() -> PlanOutcome? {
        guard let type = PlanOutcomeType(rawValue: outcome) else { return nil }
        return PlanOutcome(
            outcome: type,
            groupSize: groupSize,
            category: RequestCategory(rawValue: category) ?? .unknown,
            hadProposedTime: hadProposedTime,
            hoursBeforePlan: hoursBeforePlan,
            at: at.dateValue()
        )
    }
}

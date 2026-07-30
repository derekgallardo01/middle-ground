import Foundation

/// Records product-usage events.
///
/// Every method is fire-and-forget: a failed analytics write must never fail, delay, or roll back
/// the user action that triggered it. Call sites therefore do not `try` or `await` a result.
///
/// What is recorded is disclosed in the Privacy Policy — keep the two in step.
actor AnalyticsService {
    private let repository: EventRepository

    init(repository: EventRepository) {
        self.repository = repository
    }

    func track(
        _ type: EventType,
        userID: String,
        requestID: String? = nil,
        relationshipID: String? = nil,
        metadata: [String: String] = [:]
    ) async {
        await repository.record(
            AnalyticsEvent(
                userID: userID,
                type: type,
                requestID: requestID,
                relationshipID: relationshipID,
                metadata: metadata
            )
        )
    }

    /// Convenience for the response path, which is the highest-signal event in the product.
    func trackResponse(_ response: ResponseType, to request: Request, by userID: String) async {
        await track(
            .requestResponded,
            userID: userID,
            requestID: request.id,
            metadata: ["response": response.rawValue, "category": request.category.rawValue]
        )
    }
}

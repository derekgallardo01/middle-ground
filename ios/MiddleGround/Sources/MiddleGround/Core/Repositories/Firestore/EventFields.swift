import Foundation

/// The wire names of the fields on an `events` document.
///
/// These exist because `activeUsers` filtered on `"name"` — a field no event has ever carried,
/// since `EventDTO` writes the event type as `type`. Firestore does not object to a query on a
/// field that does not exist; it simply matches nothing. So daily and weekly actives read zero
/// for every user the app has ever had, and read as a real answer rather than a broken one.
///
/// It failed louder than that in the end, and only by luck: pairing the phantom field with a
/// range on `at` asks for a composite index nobody had declared, which fails the whole overview
/// with FAILED_PRECONDITION. Had the second filter not been there, the number would still be
/// wrong today and nothing would have said so.
///
/// A shared constant is the cheap half of the fix; `EventFieldNameTests` is the half that keeps
/// it honest, by asserting these are the keys the DTO actually encodes.
enum EventField {
    static let type = "type"
    static let at = "at"
    static let userID = "userID"
    static let metadata = "metadata"
}

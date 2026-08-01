import Foundation

/// A real, named place worth suggesting when someone fills in "Where?".
///
/// Curated in Firestore rather than compiled in. The objection to a curated list has always been
/// that it goes stale — a restaurant closes, moves, or changes its name — and a hardcoded list
/// makes that a code change and an App Store submission. Held in a collection anyone with the
/// admin flag can edit, "stale" becomes a thirty-second fix instead of a release.
///
/// This is the half of the restaurants idea that needs no partnership. OpenTable reservations
/// still do; suggesting a place people already know does not.
struct Venue: Identifiable, Codable, Sendable, Equatable, Hashable {
    let id: String
    var name: String
    /// Where it is, shown beside the name. A list spanning more than one city is misleading
    /// without it — "Joe's Pizza" means nothing if the reader is four hundred miles away.
    var city: String
    /// Which kinds of plan this place suits. A venue with none is offered for every category,
    /// which is the right default for somewhere genuinely general like a park.
    var categories: [RequestCategory]
    var emoji: String
    /// Optional street address, used to open the right pin in Maps rather than a name search.
    var address: String?
    /// Curated order. Lower sorts first, so the operator can put the good ones at the front
    /// without renaming anything.
    var rank: Int

    init(
        id: String = UUID().uuidString,
        name: String,
        city: String,
        categories: [RequestCategory] = [],
        emoji: String = "📍",
        address: String? = nil,
        rank: Int = 0
    ) {
        self.id = id
        self.name = name
        self.city = city
        self.categories = categories
        self.emoji = emoji
        self.address = address
        self.rank = rank
    }

    func suits(_ category: RequestCategory) -> Bool {
        categories.isEmpty || categories.contains(category)
    }

    /// What goes in the request's `location` field when someone taps this.
    ///
    /// The name alone, not "name, city". The field is what the other person reads on the plan,
    /// and they already know which city they live in.
    var locationText: String { name }
}

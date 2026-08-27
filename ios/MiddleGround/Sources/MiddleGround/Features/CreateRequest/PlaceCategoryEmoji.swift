import Foundation

/// A face for a place Apple classified.
///
/// The nearby search already asks MapKit for a point-of-interest category and turns it into a
/// readable word — `MapKitPlaceDiscoveryProvider.readableCategory` renders
/// `MKPOICategoryMovieTheater` as "Movie Theater". That word is on `DiscoveredPlace.category`
/// and was used for nothing but a subtitle. Choosing a place already tells the app what kind of
/// evening this is; this is what lets the plan wear it.
///
/// Nil for anything unrecognised, deliberately. The caller falls back to whatever is already
/// chosen — the category's own emoji — which is a better answer than a generic pin. A wrong face
/// is worse than a plain one, and Apple's taxonomy is longer than the list the search asks for.
enum PlaceCategoryEmoji {

    /// The categories `PlaceKind.pointOfInterestCategories` actually searches, in the readable
    /// form the provider produces, plus the few near neighbours a search returns anyway.
    ///
    /// Keyed on the readable word rather than the raw `MKPOICategory` identifier because that is
    /// what survives onto `DiscoveredPlace` — the raw value is gone by the time anything here can
    /// see it, and the fixtures used by the tour and the tests carry the readable form too.
    private static let byCategory: [String: String] = [
        // Food
        "Restaurant": "🍽️",
        "Cafe": "☕️",
        "Bakery": "🥐",
        "Food Market": "🛒",
        // Drinks
        "Brewery": "🍺",
        "Winery": "🍷",
        "Nightlife": "🍸",
        // Stay
        "Hotel": "🏨",
        // Events
        "Music Venue": "🎵",
        "Theater": "🎭",
        "Movie Theater": "🎬",
        "Stadium": "🏟️",
        "Amusement Park": "🎢",
        "Museum": "🏛️",
        "Park": "🌳"
    ]

    /// The emoji for a readable category, or nil when it is not one we have a face for.
    static func forPointOfInterest(_ category: String?) -> String? {
        guard let category else { return nil }
        return byCategory[category]
    }
}

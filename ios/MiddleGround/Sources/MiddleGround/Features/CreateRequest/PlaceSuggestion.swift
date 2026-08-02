import Foundation

/// Kinds of place a plan tends to happen at, offered when filling in "Where?".
///
/// Deliberately generic rather than a list of named venues. A curated list of real restaurants
/// would be stale the week it shipped, wrong outside whatever city it was written for, and is
/// the half of the restaurants idea that actually needs a partnership. These are prompts — the
/// field stays free text, and typing a real place name is always the better answer.
struct PlaceSuggestion: Identifiable, Hashable, Sendable {
    let id: String
    let emoji: String
    let name: String

    /// Suggestions worth offering for a given category, most likely first.
    ///
    /// Categories with no obvious venue return nothing rather than padding: "Daily Life" is
    /// mostly things that happen at home, and offering "restaurant" for splitting the chores
    /// would be noise.
    static func forCategory(_ category: RequestCategory) -> [PlaceSuggestion] {
        switch category {
        case .dating, .relationship:
            return [
                PlaceSuggestion(id: "restaurant", emoji: "🍽️", name: "Restaurant"),
                PlaceSuggestion(id: "bar", emoji: "🍸", name: "Bar"),
                PlaceSuggestion(id: "cinema", emoji: "🎬", name: "Cinema"),
                PlaceSuggestion(id: "walk", emoji: "🌳", name: "Park")
            ]
        case .chill:
            return [
                PlaceSuggestion(id: "home", emoji: "🏠", name: "Home"),
                PlaceSuggestion(id: "cafe", emoji: "☕️", name: "Café"),
                PlaceSuggestion(id: "cinema", emoji: "🎬", name: "Cinema")
            ]
        case .friends:
            return [
                PlaceSuggestion(id: "bar", emoji: "🍸", name: "Bar"),
                PlaceSuggestion(id: "restaurant", emoji: "🍽️", name: "Restaurant"),
                PlaceSuggestion(id: "gym", emoji: "🏋️", name: "Gym"),
                PlaceSuggestion(id: "home", emoji: "🏠", name: "Home")
            ]
        case .family:
            return [
                PlaceSuggestion(id: "home", emoji: "🏠", name: "Home"),
                PlaceSuggestion(id: "restaurant", emoji: "🍽️", name: "Restaurant"),
                PlaceSuggestion(id: "park", emoji: "🌳", name: "Park")
            ]
        case .travel:
            return [
                PlaceSuggestion(id: "airport", emoji: "✈️", name: "Airport"),
                PlaceSuggestion(id: "station", emoji: "🚉", name: "Station"),
                PlaceSuggestion(id: "hotel", emoji: "🏨", name: "Hotel")
            ]
        case .spontaneous:
            return [
                PlaceSuggestion(id: "cafe", emoji: "☕️", name: "Café"),
                PlaceSuggestion(id: "park", emoji: "🌳", name: "Park"),
                PlaceSuggestion(id: "bar", emoji: "🍸", name: "Bar")
            ]
        case .daily, .unknown:
            return []
        }
    }
}

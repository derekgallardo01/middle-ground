import Foundation

/// What a plan looks like at a glance.
///
/// The first person to use this app said the feed "feels like a list" and "needs emojis", and the
/// screenshots agree with him. Every card was the same white rectangle carrying the same 14pt
/// monochrome glyph, because the glyph came from the *category* — and for a couple almost every
/// plan is `relationship`. Three cards in a row read "Coffee tomorrow?", "Drinks on Wednesday?"
/// and "Date night this Friday?" above three identical hearts. An icon that is always the same is
/// not information, it is decoration that costs a row of pixels.
///
/// The app already owned the vocabulary. `ResponseType.emoji` puts ✅ 🤝 ❌ on the buttons *inside*
/// the card; `PlaceSuggestion` maps place kinds to 🍽️ 🍸 🎬 🌳 🏠 ☕️; `Venue.emoji` is curated per
/// real place and editable from the admin panel. The feed was the one surface that opted out of
/// all three, and the venue emoji was thrown away at the moment of composing.
///
/// So this is stored rather than derived. A guess made at *render* time is a guess nobody can
/// correct; a guess made once at *compose* time is a suggestion sitting in a picker, and the
/// person who knows what the evening is can change it before they send it.
extension Request {

    /// The emoji to show for this plan.
    ///
    /// The stored one, or the category's when there is none — which is every plan written before
    /// the picker existed. Those keep the old behaviour with colour added rather than being
    /// backfilled to a guess.
    var displayEmoji: String {
        let chosen = emoji?.trimmingCharacters(in: .whitespaces)
        // An empty string is not a choice. It can reach here from the admin venue editor, whose
        // own field is free text, and it would render as a hole where the face should be.
        if let chosen, !chosen.isEmpty { return chosen }
        return category.emoji
    }
}

extension RequestCategory {

    /// The fallback face, one per category.
    ///
    /// Deliberately the same idea as `iconName`, which these do not replace — the SF Symbol is
    /// still what the compose picker and the category rows use, where a category *is* the thing
    /// being chosen and eight identical-weight glyphs read as a set. This is for the feed, where
    /// the plan is the thing and the category is only a fallback.
    var emoji: String {
        switch self {
        case .relationship: return "❤️"
        case .friends: return "👋"
        case .family: return "🏠"
        case .daily: return "📋"
        case .travel: return "✈️"
        case .spontaneous: return "⚡️"
        case .dating: return "🌹"
        case .chill: return "🛋️"
        case .unknown: return "📌"
        }
    }
}

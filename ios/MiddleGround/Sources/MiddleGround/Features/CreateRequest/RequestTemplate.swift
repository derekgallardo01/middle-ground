import Foundation

/// A one-tap starting point for the decisions people make most often.
///
/// Deliberately not a new kind of request. A template only prefills the compose sheet's title and
/// category — what it produces is an ordinary `Request`, so negotiation, the calendar, security
/// rules and gamification all treat it exactly like a typed one. Adding a template needs no model,
/// DTO or rules change, which is the whole point: "what are we watching tonight?" should cost a
/// line here, not a feature.
struct RequestTemplate: Identifiable, Hashable, Sendable {
    let id: String
    let emoji: String
    let title: String
    let category: RequestCategory

    /// Offered on the compose sheet, most-used first.
    static let all: [RequestTemplate] = [
        RequestTemplate(id: "watch", emoji: "📺", title: "What are we watching tonight?", category: .chill),
        RequestTemplate(id: "eat", emoji: "🍜", title: "What are we eating tonight?", category: .chill),
        RequestTemplate(id: "date", emoji: "💛", title: "Date night this week?", category: .dating),
        RequestTemplate(id: "walk", emoji: "🚶", title: "Go for a walk?", category: .spontaneous),
        RequestTemplate(id: "chores", emoji: "🧺", title: "Split the chores this week?", category: .daily)
    ]
}

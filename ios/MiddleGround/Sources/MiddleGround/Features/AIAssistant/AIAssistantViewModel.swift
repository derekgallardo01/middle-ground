import Foundation

@MainActor
@Observable
final class AIAssistantViewModel {
    var suggestions: [AISuggestion] = []
    var isLoading = false
    var errorMessage: String?
    
    init() {
        loadMockSuggestions()
    }
    
    func loadMockSuggestions() {
        suggestions = [
            AISuggestion(
                id: "s1",
                title: "Date night idea",
                message: "You haven't had a date night in 3 weeks. Saturday evening looks free for both of you.",
                action: "Plan date night",
                requestTemplate: RequestTemplate(
                    category: .relationship,
                    title: "Date night this Saturday?",
                    details: "It's been 3 weeks — want to try something new?"
                )
            ),
            AISuggestion(
                id: "s2",
                title: "Dinner decision",
                message: "You've had pizza three times this week. How about trying that new Thai place?",
                action: "Suggest dinner",
                requestTemplate: RequestTemplate(
                    category: .daily,
                    title: "Thai food for dinner?",
                    details: "New spot on Main Street — 7pm?"
                )
            ),
            AISuggestion(
                id: "s3",
                title: "Weekend plan",
                message: "The weather looks perfect on Sunday. Your friends are all free in the afternoon.",
                action: "Plan something",
                requestTemplate: RequestTemplate(
                    category: .friends,
                    title: "Sunday afternoon outdoors?",
                    details: "Weather looks great — picnic or hike?"
                )
            )
        ]
    }
    
    func generateSuggestions() async {
        isLoading = true
        errorMessage = nil
        
        // TODO: Call Cloud Function with context (calendar, preferences, recent requests)
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        loadMockSuggestions()
        
        isLoading = false
    }
}

struct AISuggestion: Identifiable {
    let id: String
    let title: String
    let message: String
    let action: String
    let requestTemplate: RequestTemplate
}

struct RequestTemplate {
    let category: RequestCategory
    let title: String
    let details: String?
}

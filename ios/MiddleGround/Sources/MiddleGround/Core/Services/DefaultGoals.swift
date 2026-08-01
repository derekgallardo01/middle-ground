import Foundation

/// The goals shown on the Activities tab.
///
/// Kept apart from the service because this is content, not behaviour: adding a goal should read
/// as editing a list. Each one names the metric it measures, so a new entry needs no matching
/// branch anywhere else — progress used to be resolved by switching on hardcoded IDs with
/// `default: progress = 0`, which meant a goal added without editing that switch silently sat at
/// zero forever and could never unlock.
extension GamificationService {
    // Not `private`: in an extension that is file scope, and the service lives next door.
    var defaultAchievements: [Achievement] {
        [
            Achievement(
                id: "ach_1",
                title: "Great Communicator",
                description: "Resolved 10 requests through compromise",
                iconName: "trophy.fill",
                requiredValue: 10,
                unlockedAt: nil,
                metric: .negotiated
            ),
            Achievement(
                id: "ach_2",
                title: "Weekend Warrior",
                description: "Planned 5 weekend activities together",
                iconName: "airplane",
                requiredValue: 5,
                unlockedAt: nil,
                metric: .weekendAccepted
            ),
            Achievement(
                id: "ach_3",
                title: "Streak Starter",
                description: "Complete a request 3 days in a row",
                iconName: "flame.fill",
                requiredValue: 3,
                unlockedAt: nil,
                metric: .streakDays
            ),
            Achievement(
                id: "ach_4",
                title: "Master Compromiser",
                description: "Resolve 50 requests through negotiation",
                iconName: "handshake.fill",
                requiredValue: 50,
                unlockedAt: nil,
                metric: .negotiated
            ),

            // Per-activity goals — what the metric on a goal is actually for. Adding another is
            // one entry here, with no matching branch to remember elsewhere.
            Achievement(
                id: "goal_dating",
                title: "Making Time",
                description: "Earn 200 XP planning dates",
                iconName: "heart.circle.fill",
                requiredValue: 200,
                unlockedAt: nil,
                metric: .categoryXP,
                category: .dating
            ),
            Achievement(
                id: "goal_chill",
                title: "Well Rested",
                description: "Earn 200 XP on low-key plans",
                iconName: "sofa.fill",
                requiredValue: 200,
                unlockedAt: nil,
                metric: .categoryXP,
                category: .chill
            ),
            Achievement(
                id: "goal_travel",
                title: "Getting Away",
                description: "Earn 150 XP planning trips",
                iconName: "airplane.departure",
                requiredValue: 150,
                unlockedAt: nil,
                metric: .categoryXP,
                category: .travel
            ),
            Achievement(
                id: "goal_yes",
                title: "Up For It",
                description: "Say yes 25 times",
                iconName: "hand.thumbsup.fill",
                requiredValue: 25,
                unlockedAt: nil,
                metric: .accepted
            )
        ]
    }
}

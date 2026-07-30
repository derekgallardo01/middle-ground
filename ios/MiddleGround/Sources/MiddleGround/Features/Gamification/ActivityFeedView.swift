import SwiftUI

struct ActivityFeedView: View {
    let activities: [Activity]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Activity")
                .mgFont(.h2)

            LazyVStack(spacing: 10) {
                ForEach(activities) { activity in
                    ActivityRow(activity: activity)
                }
            }
        }
    }
}

struct ActivityRow: View {
    let activity: Activity

    @ScaledMetric(relativeTo: .body) private var iconWell: CGFloat = 44
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 18

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(activityColor.opacity(0.12))
                    .frame(width: iconWell, height: iconWell)

                Image(systemName: activityIcon)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(activityColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(activity.title)
                    .mgFont(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(MGColors.slate)

                if let subtitle = activity.subtitle {
                    Text(subtitle)
                        .mgFont(.bodySmall)
                        .foregroundStyle(MGColors.warm600)
                }
            }

            Spacer()

            Text(activity.timestamp, style: .time)
                .mgFont(.caption)
                .foregroundStyle(MGColors.warm600)
        }
        .padding(14)
        .background(MGColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var activityColor: Color {
        switch activity.type {
        case .streakUpdate: return MGColors.coral
        case .xpEarned: return MGColors.indigo
        case .achievementUnlocked: return MGColors.sunshine
        case .milestoneReached: return MGColors.teal
        case .moodLogged: return MGColors.sky
        case .memoryAdded: return MGColors.lavender
        }
    }

    private var activityIcon: String {
        switch activity.type {
        case .streakUpdate: return "flame.fill"
        case .xpEarned: return "bolt.fill"
        case .achievementUnlocked: return "trophy.fill"
        case .milestoneReached: return "flag.fill"
        case .moodLogged: return "face.smiling"
        case .memoryAdded: return "photo.fill"
        }
    }
}

#Preview {
    ActivityFeedView(activities: [
        Activity(userID: "user_1", type: .streakUpdate, title: "12 day streak", subtitle: "Keep it going!", value: 12),
        Activity(userID: "user_1", type: .xpEarned, title: "+25 XP", subtitle: "Accepted a request", value: 25)
    ])
    .padding()
    .background(MGColors.sand)
}

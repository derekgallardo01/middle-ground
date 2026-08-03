import SwiftUI

/// Who turns up most, within one group.
///
/// Friendly on purpose, and the copy carries most of that weight. There is a first place because
/// that is the fun of it, but there is no last place, no red, no "worst" — the people at the
/// bottom are simply lower down a list. The people still building history sit under a separate
/// heading rather than at the end of the ranking, because being new is not a poor score.
///
/// Says where the numbers come from. Each member sees a board built from the plans *they* were
/// part of, so two people in the same group can see different boards — stating that is better
/// than implying a precision the data does not have. See `GroupScoreboard`.
struct ScoreboardCard: View {
    let groupName: String
    let board: GroupScoreboard
    let currentUserID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: MGSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Turning up in \(groupName)")
                    .mgFont(.h2)
                // Explicit about scope, because the "Turning up" card directly above counts
                // every plan and this one counts only this group's — so your own number can
                // differ between the two, and an unexplained mismatch reads as a bug.
                Text("Plans in this group that you were part of.")
                    .mgFont(.bodySmall)
                    .foregroundStyle(MGColors.warm600)
            }

            VStack(spacing: MGSpacing.sm) {
                ForEach(board.ranked) { entry in
                    row(entry)
                }
            }

            if !board.unranked.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: MGSpacing.xs) {
                    Text("Still settling in")
                        .mgFont(.bodySmall)
                        .foregroundStyle(MGColors.warm600)
                    Text(board.unranked.map(\.displayName).formatted(.list(type: .and)))
                        .mgFont(.bodySmall)
                }
            }
        }
        .mgSurfaceCard()
    }

    private func row(_ entry: GroupScoreboard.Entry) -> some View {
        let isYou = entry.userID == currentUserID
        return HStack(spacing: MGSpacing.md) {
            Text("\(entry.rank ?? 0)")
                .mgFont(.bodySmall)
                .monospacedDigit()
                .foregroundStyle(MGColors.warm600)
                .frame(width: 18, alignment: .trailing)

            Text(isYou ? "You" : entry.displayName)
                .mgFont(.body)
                .fontWeight(isYou ? .semibold : .regular)

            Spacer(minLength: MGSpacing.sm)

            if let percentage = entry.percentage {
                Text("\(percentage)%")
                    .mgFont(.body)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(entry.rank ?? 0). \(isYou ? "You" : entry.displayName), \(entry.percentage ?? 0) percent"
        )
    }
}

#Preview {
    let board = GroupScoreboard(entries: [
        .init(
            userID: "a",
            displayName: "Alice",
            score: ReliabilityScore(attended: 9, missed: 1, lateCancellations: 0, cancellationStreak: 0),
            rank: 1
        ),
        .init(
            userID: "b",
            displayName: "Bob",
            score: ReliabilityScore(attended: 6, missed: 2, lateCancellations: 2, cancellationStreak: 1),
            rank: 2
        ),
        .init(
            userID: "c",
            displayName: "Carol",
            score: ReliabilityScore(attended: 1, missed: 0, lateCancellations: 0, cancellationStreak: 0),
            rank: nil
        )
    ])
    return ScoreboardCard(groupName: "Sunday Club", board: board, currentUserID: "b")
        .padding()
}

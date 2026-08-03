import SwiftUI

/// Where a group plan currently stands: who is coming, and who still owes an answer.
///
/// Both numbers already existed — `attendeeIDs` and `awaitingResponseFrom` are computed on
/// `Request` and were displayed nowhere at all. On a plan with five people that meant a change of
/// time produced a status badge and no way to tell who was back in, which is the itch a voting
/// feature would have been built to scratch. It is not a missing vote; it is a missing sentence.
///
/// Deliberately not a vote. A change of plan re-opens the question and the plan re-forms around
/// whoever says yes — nobody is out-voted out of their own evening. This row just says so.
struct GroupStatusRow: View {
    let attendeeNames: [String]
    let awaitingNames: [String]
    /// Shown when everyone has answered and there is nothing left to wait for.
    let isSettled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: MGSpacing.xs) {
            if !attendeeNames.isEmpty {
                Label {
                    Text(inLine)
                        .mgFont(.bodySmall)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(MGColors.teal)
                }
            }

            if !awaitingNames.isEmpty {
                Label {
                    Text("Waiting on \(awaitingNames.formatted(.list(type: .and)))")
                        .mgFont(.bodySmall)
                        .foregroundStyle(MGColors.warm600)
                } icon: {
                    Image(systemName: "clock")
                        .foregroundStyle(MGColors.warm600)
                }
            } else if !isSettled && !attendeeNames.isEmpty {
                // A Label like the others, not a bare Text: without the icon it hangs off the
                // left edge while every line above it is indented past one.
                Label {
                    Text("Everyone's answered.")
                        .mgFont(.bodySmall)
                        .foregroundStyle(MGColors.warm600)
                } icon: {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(MGColors.warm600)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// "Alex and Sam are in" / "Alex is in" — the verb has to agree, or it reads as broken English
    /// on exactly the plans a group product is for.
    private var inLine: String {
        let names = attendeeNames.formatted(.list(type: .and))
        return attendeeNames.count == 1 ? "\(names) is in" : "\(names) are in"
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 20) {
        GroupStatusRow(
            attendeeNames: ["You", "Alex"],
            awaitingNames: ["Jordan"],
            isSettled: false
        )
        GroupStatusRow(attendeeNames: ["Alex"], awaitingNames: [], isSettled: false)
        GroupStatusRow(
            attendeeNames: ["You", "Alex", "Sam"],
            awaitingNames: [],
            isSettled: true
        )
    }
    .padding()
}

import SwiftUI

struct StreakView: View {
    let days: Int
    /// Real per-day completion for the current week; defaults to an empty week.
    var weekDays: [Bool] = Array(repeating: false, count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("🔥")
                    .font(.system(size: 40))

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(days) day streak")
                        .mgFont(.h2)
                    Text("You're building healthy habits together.")
                        .mgFont(.bodySmall)
                }
            }

            HStack(spacing: 8) {
                ForEach(0..<7, id: \.self) { index in
                    let isCompleted = index < weekDays.count ? weekDays[index] : false
                    DayPill(day: dayLetter(for: index), isCompleted: isCompleted)
                }
            }
        }
        .padding(20)
        .background(MGColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: MGRadius.lg, style: .continuous))
        .mgShadow(MGShadow.md)
    }

    private func dayLetter(for index: Int) -> String {
        let days = ["S", "M", "T", "W", "T", "F", "S"]
        return days[index]
    }
}

struct DayPill: View {
    let day: String
    let isCompleted: Bool

    var body: some View {
        Text(day)
            .mgFont(.caption)
            .fontWeight(.bold)
            .foregroundStyle(isCompleted ? MGColors.onAccent : MGColors.warm600)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isCompleted ? MGColors.coral : MGColors.warm100)
            .clipShape(Capsule())
    }
}

#Preview {
    StreakView(days: 12, weekDays: [true, true, true, true, false, true, true])
        .padding()
        .background(MGColors.sand)
}

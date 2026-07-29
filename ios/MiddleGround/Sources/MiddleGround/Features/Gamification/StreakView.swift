import SwiftUI

struct StreakView: View {
    let days: Int
    let weekDays: [Bool] = [true, true, true, true, false, true, true]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("🔥")
                    .font(.system(size: 40))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(days) day streak")
                        .font(MGFonts.h2)
                    Text("You're building healthy habits together.")
                        .font(MGFonts.bodySmall)
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
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: MGColors.slate.opacity(0.05), radius: 12, x: 0, y: 4)
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
            .font(MGFonts.caption)
            .fontWeight(.bold)
            .foregroundStyle(isCompleted ? .white : MGColors.warm600)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isCompleted ? MGColors.coral : MGColors.warm100)
            .clipShape(Capsule())
    }
}

#Preview {
    StreakView(days: 12)
        .padding()
        .background(MGColors.sand)
}

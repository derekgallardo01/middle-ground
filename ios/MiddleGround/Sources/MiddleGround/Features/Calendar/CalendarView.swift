import SwiftUI

struct CalendarView: View {
    @State private var viewModel = CalendarViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if viewModel.isLoading {
                        LoadingSkeleton(type: .calendar)
                    } else if let errorMessage = viewModel.errorMessage {
                        ErrorState(message: errorMessage) {
                            Task { await viewModel.loadEvents() }
                        }
                    } else {
                        monthHeader
                        calendarGrid
                        upcomingEvents
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(MGColors.sand.ignoresSafeArea())
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                await viewModel.loadEvents()
            }
        }
        .task {
            await viewModel.loadCurrentUser()
            await viewModel.loadEvents()
        }
    }

    private var monthHeader: some View {
        HStack {
            Button {
                viewModel.changeMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .foregroundStyle(MGColors.slate)
                    .padding(12)
                    .background(MGColors.surface)
                    .clipShape(Circle())
            }
            .buttonStyle(ScaleButtonStyle())

            Spacer()

            Text(viewModel.currentMonth, formatter: monthFormatter)
                .mgFont(.h2)

            Spacer()

            Button {
                viewModel.changeMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .foregroundStyle(MGColors.slate)
                    .padding(12)
                    .background(MGColors.surface)
                    .clipShape(Circle())
            }
            .buttonStyle(ScaleButtonStyle())
        }
    }

    private var calendarGrid: some View {
        VStack(spacing: 8) {
            HStack {
                ForEach(Calendar.current.shortWeekdaySymbols, id: \.self) { day in
                    Text(day)
                        .mgFont(.caption)
                        .foregroundStyle(MGColors.warm600)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                ForEach(daysInMonth, id: \.self) { date in
                    DayCell(
                        date: date,
                        isSelected: Calendar.current.isDate(date, inSameDayAs: viewModel.selectedDate),
                        hasEvents: !viewModel.events(for: date).isEmpty,
                        isCurrentMonth: Calendar.current.isDate(date, equalTo: viewModel.currentMonth, toGranularity: .month)
                    )
                    .onTapGesture {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                            viewModel.selectedDate = date
                        }
                        Haptics.shared.impact(.light)
                    }
                }
            }
        }
        .padding(16)
        .background(MGColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .mgShadow(MGShadow.md)
    }

    private var upcomingEvents: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Upcoming")
                .mgFont(.h2)

            let upcoming = viewModel.events
                .compactMap { request -> (Request, Date)? in
                    guard let date = request.proposedTime else { return nil }
                    return (request, date)
                }
                .filter { $0.1 >= Date().startOfDay }
                .sorted { $0.1 < $1.1 }
                .prefix(5)
                .map { $0.0 }

            if upcoming.isEmpty {
                ContentUnavailableView {
                    Label("No upcoming plans", systemImage: "calendar.badge.clock")
                } description: {
                    Text("Accepted requests with dates will show here.")
                }
                .background(MGColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else {
                ForEach(upcoming) { request in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(request.title)
                                .mgFont(.body)
                                .fontWeight(.semibold)
                            if let time = request.proposedTime {
                                Text(time, style: .date)
                                    .mgFont(.caption)
                                    .foregroundStyle(MGColors.warm600)
                            }
                        }
                        Spacer()
                        StatusBadge(status: request.status)
                    }
                    .padding(14)
                    .background(MGColors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
    }

    private var daysInMonth: [Date] {
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: viewModel.currentMonth) else { return [] }

        var dates: [Date] = []
        var date = monthInterval.start

        // Add leading days from previous month
        let weekdayOffset = calendar.component(.weekday, from: date) - 1
        date = calendar.date(byAdding: .day, value: -weekdayOffset, to: date) ?? date

        // Build 6 weeks of days
        for _ in 0..<42 {
            dates.append(date)
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        }

        return dates
    }

    private var monthFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }
}

struct DayCell: View {
    @ScaledMetric(relativeTo: .caption) private var selectionSize: CGFloat = 36
    @ScaledMetric(relativeTo: .caption) private var rowHeight: CGFloat = 44

    let date: Date
    let isSelected: Bool
    let hasEvents: Bool
    let isCurrentMonth: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isSelected ? MGColors.indigo : Color.clear)
                .frame(width: selectionSize, height: selectionSize)

            Text("\(Calendar.current.component(.day, from: date))")
                .mgFont(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(isSelected ? .white : (isCurrentMonth ? MGColors.slate : MGColors.warm600))

            if hasEvents && !isSelected {
                Circle()
                    .fill(MGColors.coral)
                    .frame(width: 5, height: 5)
                    .offset(y: 10)
            }
        }
        .frame(height: rowHeight)
    }
}

extension Date {
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }
}

#Preview {
    AppConfiguration.useMockRepositories = true
    return CalendarView()
}

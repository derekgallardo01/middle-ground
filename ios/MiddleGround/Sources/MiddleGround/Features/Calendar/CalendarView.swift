import SwiftUI

struct CalendarView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewModel = CalendarViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Gated on having loaded, not on `isLoading` — see CalendarViewModel.
                    if !viewModel.hasLoaded {
                        LoadingSkeleton(type: .calendar)
                    } else if let errorMessage = viewModel.errorMessage {
                        ErrorState(message: errorMessage) {
                            Task { await viewModel.loadEvents() }
                        }
                    } else {
                        monthHeader
                        calendarGrid
                        availabilityPanel
                        upcomingEvents
                    }
                }
                .padding(.horizontal, 16)
                .mgReadableWidth()
                .padding(.vertical, 12)
            }
            .background(MGColors.sand.ignoresSafeArea())
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                await viewModel.loadEvents()
                await viewModel.loadAvailability()
            }
            // Marking yourself away is a message to other people, so a write that reached nobody
            // has to be said out loud. It cannot use the error state above: that one replaces the
            // whole calendar, which loaded perfectly well.
            .alert("Oops", isPresented: .constant(viewModel.availabilityErrorMessage != nil)) {
                Button("OK") { viewModel.availabilityErrorMessage = nil }
            } message: {
                Text(viewModel.availabilityErrorMessage ?? "")
            }
        }
        .task {
            await viewModel.loadCurrentUser()
            await viewModel.loadEvents()
            // Must come after loadCurrentUser: it needs an ID to know whose blocks are whose,
            // and it returns silently without one. Missing it here left the panel empty until
            // the user happened to pull to refresh.
            await viewModel.loadAvailability()
            // Last, and on purpose: it never returns. SwiftUI cancels it when the tab goes away.
            await viewModel.observeAvailability()
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
            // Announced as "chevron left, button" without this — and these are the only way
            // to change month.
            .accessibilityLabel("Previous month")

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
            .accessibilityLabel("Next month")
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
                        isCurrentMonth: Calendar.current.isDate(date, equalTo: viewModel.currentMonth, toGranularity: .month),
                        someoneIsBusy: viewModel.someoneIsBusy(on: date),
                        youAreBusy: viewModel.isMarkedUnavailable(on: date)
                    )
                    .onTapGesture {
                        withAnimation(reduceMotion ? nil : MGMotion.tap) {
                            viewModel.selectedDate = date
                        }
                        Haptics.shared.impact(.light)
                    }
                }
            }
        }
        .padding(16)
        .background(MGColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: MGRadius.lg, style: .continuous))
        .mgShadow(MGShadow.md)
    }

    /// Who is not free on the selected day, and a way to say you are not either.
    ///
    /// Nothing here comes from anybody's calendar — see `UnavailableBlock`. It shows only what
    /// people deliberately blocked out, which is why it can be shown to a group at all.
    private var availabilityPanel: some View {
        VStack(alignment: .leading, spacing: MGSpacing.sm) {
            let busy = viewModel.busyNames(on: viewModel.selectedDate)
            let youAreBusy = viewModel.isMarkedUnavailable(on: viewModel.selectedDate)

            if !busy.isEmpty {
                Label {
                    // The verb has to agree, or the ordinary case in a group reads as broken.
                    Text(busy.count == 1
                         ? "\(busy[0]) isn't free"
                         : "\(busy.formatted(.list(type: .and))) aren't free")
                        .mgFont(.bodySmall)
                } icon: {
                    Image(systemName: "person.crop.circle.badge.exclamationmark")
                        .foregroundStyle(MGColors.warm600)
                }
                .foregroundStyle(MGColors.warm600)
            }

            Button {
                Task { await viewModel.toggleUnavailable(on: viewModel.selectedDate) }
            } label: {
                Label(
                    youAreBusy ? "I'm free again this day" : "I'm not free this day",
                    systemImage: youAreBusy ? "arrow.uturn.backward" : "nosign"
                )
                .mgFont(.bodySmall)
                .foregroundStyle(youAreBusy ? MGColors.warm600 : MGColors.indigo)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("toggleUnavailable")

            Text("Only the days you block out are shared. Your calendar is never uploaded.")
                .mgFont(.caption)
                .foregroundStyle(MGColors.warm400)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mgSurfaceCard()
    }

    private var upcomingEvents: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.hasSelectionWithEvents
                 ? viewModel.selectedDate.formatted(date: .abbreviated, time: .omitted)
                 : "Upcoming")
                .mgFont(.h2)

            let upcoming = viewModel.listedEvents

            if upcoming.isEmpty && viewModel.groups.hasNobodyToPlanWith {
                // "No upcoming plans" is true and useless to somebody who has nobody to make one
                // with. Until then the whole app is inert, and this screen used to say nothing
                // about the one action that changes that.
                InvitePrompt(code: viewModel.soleInviteCode)
            } else if upcoming.isEmpty {
                ContentUnavailableView {
                    Label("No upcoming plans", systemImage: "calendar.badge.clock")
                } description: {
                    Text("Accepted requests with dates will show here.")
                }
                .background(MGColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: MGRadius.lg, style: .continuous))
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
                    .clipShape(RoundedRectangle(cornerRadius: MGRadius.md, style: .continuous))
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
    /// Somebody in one of your groups has blocked this day out.
    var someoneIsBusy: Bool = false
    /// You have blocked it out yourself.
    var youAreBusy: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .fill(isSelected ? MGColors.indigo : Color.clear)
                .frame(width: selectionSize, height: selectionSize)

            Text("\(Calendar.current.component(.day, from: date))")
                .mgFont(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(isSelected ? MGColors.onAccent : (isCurrentMonth ? MGColors.slate : MGColors.warm600))

            // Two different facts, so two different marks rather than one ambiguous dot:
            // coral means something is planned, warm means somebody is not free.
            if !isSelected {
                HStack(spacing: 3) {
                    if hasEvents {
                        Circle().fill(MGColors.coral).frame(width: 5, height: 5)
                    }
                    if someoneIsBusy || youAreBusy {
                        Circle().fill(MGColors.warm400).frame(width: 5, height: 5)
                    }
                }
                .offset(y: 10)
            }

            // A ring, not a fill: being unavailable marks the day without competing with the
            // selection, which already owns the filled circle.
            if youAreBusy {
                Circle()
                    .stroke(MGColors.warm400, lineWidth: 1.5)
                    .frame(width: selectionSize, height: selectionSize)
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

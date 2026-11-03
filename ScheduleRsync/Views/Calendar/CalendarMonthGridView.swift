import SwiftUI

struct CalendarMonthGridView: View {
    @Environment(\.calendar) private var calendar
    let date: Date
    @Binding var plannedDate: Date
    let occurrences: [ScheduledItem]
    let firstScheduledText: String?
    var lastExecutedScheduleText: String? = nil
    var sleepDelayNotice: String? = nil
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let today = calendar.startOfDay(for: context.date)
            let byDay = CalendarMonthLayout.groupedOccurrences(occurrences, calendar: calendar)
            VStack(alignment: .leading, spacing: 10) {
                Text(date, format: .dateTime.month(.wide).year())
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)

                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(CalendarMonthLayout.weekdays(calendar: calendar)) { weekday in
                        Text(weekday.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 4)
                            .accessibilityLabel(weekday.fullName)
                    }
                    ForEach(CalendarMonthLayout.days(in: date, calendar: calendar), id: \.self) { day in
                        CalendarDayView(day: day,
                                        isInMonth: calendar.isDate(day, equalTo: date, toGranularity: .month),
                                        isSelected: calendar.isDate(day, inSameDayAs: plannedDate),
                                        isToday: calendar.isDate(day, inSameDayAs: today),
                                        isPast: day < today,
                                        occurrences: byDay[calendar.startOfDay(for: day)] ?? []) {
                            plannedDate = CalendarMonthLayout.selecting(day, keepingTimeFrom: plannedDate,
                                                                        calendar: calendar, now: context.date)
                        }
                    }
                }

                HStack(spacing: 16) {
                    Label("Scheduled runs", systemImage: "clock.fill")
                        .foregroundStyle(Color.accentColor)
                    Text("Outlined day: today")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                DisclosureGroup("Calendar help") {
                    Text("Select a day to set the run date. Hover over a marked day for profiles and times. Yellow: adjusted · Red: skipped (will not run). Planned through the end of next month.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.caption)

                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Label("Next run", systemImage: "calendar.badge.clock")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(firstScheduledText ?? "No upcoming schedules")
                        .font(.callout)
                        .textSelection(.enabled)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Label("Last execution", systemImage: "checkmark.circle")
                        .font(.caption.weight(.semibold))
                    Text(lastExecutedScheduleText ?? "No scheduled run executed this session")
                        .font(.callout)
                        .textSelection(.enabled)
                }
                .foregroundStyle(lastExecutedScheduleText == nil ? Color.secondary : Color.green)
                .fixedSize(horizontal: false, vertical: true)

                if let sleepDelayNotice {
                    Label(sleepDelayNotice, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

import SwiftUI

struct CalendarDayView: View {
    let day: Date
    let isInMonth: Bool
    let isSelected: Bool
    let isToday: Bool
    let isPast: Bool
    let occurrences: [ScheduledItem]
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(spacing: 2) {
                Text(day, format: .dateTime.day())
                    .font(.body.weight(isToday || isSelected ? .bold : .medium))
                    .monospacedDigit()
                    .foregroundStyle(isInMonth ? Color.primary : Color.secondary.opacity(0.45))
                if !occurrences.isEmpty {
                    Label("\(occurrences.count)", systemImage: "clock.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(occurrences.contains { $0.isAdjusted } ? Color.yellow : Color.accentColor)
                        .padding(.horizontal, 5)
                        .background(Color.accentColor.opacity(0.12), in: .capsule)
                } else {
                    Text(" ").font(.caption2)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(isSelected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(isInMonth ? 0.035 : 0.01),
                        in: .rect(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isToday ? Color.accentColor : .clear, lineWidth: 2)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!isInMonth || isPast)
        .help(details)
        .accessibilityLabel(Text(day, format: .dateTime.weekday(.wide).day().month(.wide).year()))
        .accessibilityValue("\(occurrences.count == 1 ? "1 scheduled run" : "\(occurrences.count) scheduled runs")\(isToday ? ", today" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var details: String {
        guard !occurrences.isEmpty else { return "No scheduled runs" }
        return occurrences.map {
            "\($0.scheduledata?.profile ?? "Default") · \($0.time.formatted(date: .omitted, time: .shortened))\($0.isAdjusted ? " · Adjusted from " + $0.requestedTime.formatted(date: .omitted, time: .shortened) : "")"
        }.joined(separator: "\n")
    }
}

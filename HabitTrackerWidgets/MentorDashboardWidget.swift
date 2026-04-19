import SwiftUI
import WidgetKit

struct MentorDashboardWidget: Widget {
    let kind = "MentorDashboardWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotTimelineProvider()) { entry in
            MentorDashboardView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) { WidgetBackground() }
        }
        .configurationDisplayName("Mentor Dashboard")
        .description("Keep tabs on your mentees at a glance.")
        .supportedFamilies([.systemMedium])
    }
}

private struct MentorDashboardView: View {
    @Environment(\.colorScheme) private var scheme
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "person.2.badge.gearshape.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(WidgetPalette.violet)
                    Text("Mentees")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.primary)
                }
                Spacer()
                if let count = snapshot.backend?.activeMenteeCount {
                    Text("\(count) active")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(WidgetPalette.subtleForeground(scheme))
                }
            }

            if let mentees = snapshot.backend?.mentees, !mentees.isEmpty {
                VStack(spacing: 6) {
                    ForEach(mentees.prefix(3)) { mentee in
                        MenteeRow(mentee: mentee)
                    }
                }
            } else {
                Spacer()
                Text(snapshot.backend == nil ? "Sign in to see mentees" : "No active mentees")
                    .font(.system(size: 11))
                    .foregroundStyle(WidgetPalette.subtleForeground(scheme))
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

private struct MenteeRow: View {
    @Environment(\.colorScheme) private var scheme
    let mentee: WidgetSnapshot.BackendData.MenteeCard

    private var initials: String {
        let parts = mentee.displayName.split(separator: " ").prefix(2)
        return parts.map { String($0.prefix(1)) }.joined().uppercased()
    }

    private var statusColor: Color {
        switch mentee.consistencyPercent {
        case 80...: return WidgetPalette.success
        case 50...: return WidgetPalette.warning
        default: return WidgetPalette.accent
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(statusColor.opacity(0.18))
                Text(initials)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(statusColor)
            }
            .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(mentee.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(mentee.suggestedAction)
                    .font(.system(size: 9))
                    .foregroundStyle(WidgetPalette.subtleForeground(scheme))
                    .lineLimit(1)
            }
            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text("\(mentee.consistencyPercent)%")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(statusColor)
                if mentee.missedHabitsToday > 0 {
                    Text("\(mentee.missedHabitsToday) missed")
                        .font(.system(size: 8))
                        .foregroundStyle(WidgetPalette.warning)
                }
            }
        }
    }
}

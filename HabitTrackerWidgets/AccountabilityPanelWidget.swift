import SwiftUI
import WidgetKit

struct AccountabilityPanelWidget: Widget {
    let kind = "AccountabilityPanelWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotTimelineProvider()) { entry in
            AccountabilityPanelView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) { WidgetBackground() }
        }
        .configurationDisplayName("Accountability Panel")
        .description("Your mentor tip and your mentees in one view.")
        .supportedFamilies([.systemLarge])
    }
}

private struct AccountabilityPanelView: View {
    @Environment(\.colorScheme) private var scheme
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Accountability")
                .font(.system(size: 14, weight: .bold))

            if let backend = snapshot.backend {
                if let mentor = backend.mentor {
                    MentorBlock(mentor: mentor)
                }

                Divider().opacity(0.3)

                HStack(alignment: .firstTextBaseline) {
                    Text("Your Mentees")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WidgetPalette.subtleForeground(scheme))
                    Spacer()
                    Text("\(backend.activeMenteeCount) active")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(WidgetPalette.violet)
                }

                if backend.mentees.isEmpty {
                    Text("No mentees yet.")
                        .font(.system(size: 11))
                        .foregroundStyle(WidgetPalette.subtleForeground(scheme))
                } else {
                    VStack(spacing: 5) {
                        ForEach(backend.mentees.prefix(3)) { mentee in
                            CompactMenteeRow(mentee: mentee)
                        }
                    }
                }
            } else {
                Spacer()
                Text("Sign in to see your accountability circle")
                    .font(.system(size: 12))
                    .foregroundStyle(WidgetPalette.subtleForeground(scheme))
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            }

            Spacer(minLength: 0)
        }
        .padding(20)
    }
}

private struct MentorBlock: View {
    @Environment(\.colorScheme) private var scheme
    let mentor: WidgetSnapshot.BackendData.MentorCard

    private var initials: String {
        let parts = mentor.displayName.split(separator: " ").prefix(2)
        return parts.map { String($0.prefix(1)) }.joined().uppercased()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [WidgetPalette.violet, WidgetPalette.accent],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                Text(initials)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(mentor.displayName)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("· Mentor")
                        .font(.system(size: 10))
                        .foregroundStyle(WidgetPalette.subtleForeground(scheme))
                    Spacer()
                    Text("\(mentor.consistencyPercent)%")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(WidgetPalette.violet)
                }
                Text(mentor.tip)
                    .font(.system(size: 10))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(WidgetPalette.violet.opacity(0.08))
        )
    }
}

private struct CompactMenteeRow: View {
    @Environment(\.colorScheme) private var scheme
    let mentee: WidgetSnapshot.BackendData.MenteeCard

    private var initials: String {
        let parts = mentee.displayName.split(separator: " ").prefix(2)
        return parts.map { String($0.prefix(1)) }.joined().uppercased()
    }

    private var tint: Color {
        switch mentee.consistencyPercent {
        case 80...: return WidgetPalette.success
        case 50...: return WidgetPalette.warning
        default: return WidgetPalette.accent
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(tint.opacity(0.18))
                Text(initials)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(tint)
            }
            .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(mentee.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(mentee.suggestedAction)
                    .font(.system(size: 9))
                    .foregroundStyle(WidgetPalette.subtleForeground(scheme))
                    .lineLimit(1)
            }
            Spacer()
            Text("\(mentee.consistencyPercent)%")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(scheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
        )
    }
}

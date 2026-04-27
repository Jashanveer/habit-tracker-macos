import SwiftUI

struct ChatMessageRow: View {
    let message: AccountabilityDashboard.Message
    var isFromCurrentUser: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack {
            if isFromCurrentUser { Spacer(minLength: 40) }

            VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 2) {
                Text(message.senderName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)

                Text(Self.humanize(message.message))
                    .font(.system(size: 12))
                    .foregroundStyle(isFromCurrentUser ? .white : .primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(messageBubbleColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                if message.nudge {
                    Label("Nudge", systemImage: "hand.wave.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                }
            }

            if !isFromCurrentUser { Spacer(minLength: 40) }
        }
    }

    private var messageBubbleColor: Color {
        if isFromCurrentUser {
            return CleanShotTheme.accent
        }
        return colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color(red: 0.93, green: 0.93, blue: 0.95)
    }

    /// Strip common Markdown markers from chat content so the bubble reads as
    /// natural prose. Plain `Text` doesn't render Markdown, so without this
    /// asterisks and hashes leak through verbatim ("**One tiny move:**").
    private static func humanize(_ raw: String) -> String {
        var s = raw
        // Bold / italic emphasis — handle paired markers, longest first so
        // double markers don't get half-stripped by the single-marker pass.
        s = s.replacingOccurrences(of: #"\*\*(.+?)\*\*"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"__(.+?)__"#,     with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?<![\*\w])\*([^\*\n]+?)\*(?![\*\w])"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?<![_\w])_([^_\n]+?)_(?![_\w])"#,     with: "$1", options: .regularExpression)
        // Inline code → plain text.
        s = s.replacingOccurrences(of: #"`([^`\n]+?)`"#, with: "$1", options: .regularExpression)
        // ATX heading markers at line start.
        s = s.replacingOccurrences(of: #"(?m)^[ \t]{0,3}#{1,6}[ \t]+"#, with: "", options: .regularExpression)
        // Collapse runs of 3+ newlines to a single blank line.
        s = s.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

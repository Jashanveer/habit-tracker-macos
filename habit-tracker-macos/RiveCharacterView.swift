import AVFoundation
import SwiftUI

// MARK: - Mentor Character + Chat Bubble

/// A walking mentor character at the bottom of the window with a floating chat bubble.
struct MentorCharacterView: View {
    @ObservedObject var backend: HabitBackendStore
    @Binding var nudge: String?
    @State private var walker = WalkerState()
    @State private var chatOpen = false
    @State private var chatShown = false
    @State private var chatAnimationTask: Task<Void, Never>? = nil
    @State private var messageText = ""
    @State private var hasUnread = false
    @State private var visibleNudge: String? = nil
    @State private var nudgeShown = false
    @State private var nudgeDismissTask: Task<Void, Never>? = nil

    private let characterHeight: CGFloat = 130
    private let videoAspect: CGFloat = 1080 / 1920

    private var mentorName: String {
        backend.dashboard?.match?.mentor.displayName ?? "Mentor"
    }

    private var messages: [AccountabilityDashboard.Message] {
        backend.dashboard?.menteeDashboard.messages ?? []
    }

    private let bubbleHeight: CGFloat = 300
    private let bubbleWidth: CGFloat = 280
    private let bubbleGap: CGFloat = 8
    private let nudgeBubbleWidth: CGFloat = 180

    var body: some View {
        GeometryReader { geo in
            let charWidth = characterHeight * videoAspect
            let travelDistance = max(geo.size.width - charWidth, 0)
            let charX = walker.positionProgress * travelDistance
            let characterHeadX = charX + charWidth / 2
            // The visible character occupies ~85% of the frame (bottom 15% is ground offset)
            let visibleCharTop = characterHeight * 0.85

            LoopingVideoView(videoName: "walk-bruce-01", isPlaying: walker.isWalking)
                .frame(width: charWidth, height: characterHeight)
                .scaleEffect(x: walker.goingRight ? 1 : -1, y: 1, anchor: .center)
                .position(
                    x: charX + charWidth / 2,
                    y: geo.size.height - characterHeight / 2 + characterHeight * 0.15
                )
                .onTapGesture {
                    toggleChat()
                }

            if hasUnread && !chatOpen {
                Circle()
                    .fill(.red)
                    .frame(width: 14, height: 14)
                    .overlay(
                        Text("\(messages.count)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    )
                    .position(
                        x: charX + charWidth - 4,
                        y: geo.size.height - visibleCharTop - 4
                    )
            }

            // Chat bubble — positioned just above the character's head
            if chatOpen {
                let bubbleY = geo.size.height - visibleCharTop - bubbleGap - bubbleHeight / 2
                let bubbleCenterX = characterHeadX
                let clampedX = clamped(bubbleCenterX, lowerBound: bubbleWidth / 2 + 8, upperBound: geo.size.width - bubbleWidth / 2 - 8)
                let anchorX = (bubbleCenterX - (clampedX - bubbleWidth / 2)) / bubbleWidth
                let scaleAnchor = UnitPoint(x: clamped(anchorX, lowerBound: 0, upperBound: 1), y: 1)

                MentorChatBubble(
                    mentorName: mentorName,
                    messages: messages,
                    messageText: $messageText,
                    onSend: sendMessage,
                    onClose: {
                        closeChat()
                    }
                )
                .frame(width: bubbleWidth, height: bubbleHeight)
                .scaleEffect(chatShown ? 1 : 0.05, anchor: scaleAnchor)
                .opacity(chatShown ? 1 : 0)
                .position(x: clampedX, y: bubbleY)
                .animation(.spring(response: 0.35, dampingFraction: 0.78), value: chatShown)
                .zIndex(10)
            }

            if let text = visibleNudge {
                let nudgeCenterX = clamped(
                    characterHeadX,
                    lowerBound: nudgeBubbleWidth / 2 + 8,
                    upperBound: geo.size.width - nudgeBubbleWidth / 2 - 8
                )
                let nudgeAnchorX = (characterHeadX - (nudgeCenterX - nudgeBubbleWidth / 2)) / nudgeBubbleWidth
                let clampedNudgeAnchorX = clamped(nudgeAnchorX, lowerBound: 0, upperBound: 1)
                let nudgeAnchor = UnitPoint(x: clampedNudgeAnchorX, y: 1)
                let nudgeBubbleY = geo.size.height - visibleCharTop - bubbleGap - 22

                SpeechBubbleNudge(text: text, width: nudgeBubbleWidth, tailAnchorX: clampedNudgeAnchorX)
                    .scaleEffect(nudgeShown ? 1 : 0.01, anchor: nudgeAnchor)
                    .opacity(nudgeShown ? 1 : 0)
                    .position(x: nudgeCenterX, y: nudgeBubbleY)
                    .animation(.spring(response: 0.3, dampingFraction: 0.65), value: nudgeShown)
                    .zIndex(11)
                    .allowsHitTesting(false)
            }

            Color.clear
                .onAppear {
                    walker.travelDistance = travelDistance
                    walker.start()
                }
                .onChange(of: geo.size.width) { _, _ in
                    walker.travelDistance = travelDistance
                }
                .onChange(of: messages.count) { old, new in
                    if new > old && !chatOpen {
                        hasUnread = true
                    }
                }
                .onChange(of: nudge) { _, newValue in
                    guard let msg = newValue else { return }
                    nudgeDismissTask?.cancel()
                    nudge = nil
                    visibleNudge = msg
                    nudgeShown = false
                    DispatchQueue.main.async {
                        nudgeShown = true
                    }
                    nudgeDismissTask = Task {
                        try? await Task.sleep(for: .seconds(2))
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            nudgeShown = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                visibleNudge = nil
                            }
                        }
                    }
                }
        }
        .frame(height: chatOpen ? characterHeight + bubbleHeight + bubbleGap : characterHeight)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: chatOpen)
    }

    private func toggleChat() {
        if chatOpen {
            closeChat()
        } else {
            openChat()
        }
    }

    private func openChat() {
        chatAnimationTask?.cancel()
        hasUnread = false
        chatShown = false

        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            chatOpen = true
        }

        chatAnimationTask = Task {
            await Task.yield()
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                    chatShown = true
                }
            }
        }
    }

    private func closeChat() {
        chatAnimationTask?.cancel()

        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            chatShown = false
        }

        chatAnimationTask = Task {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    chatOpen = false
                }
            }
        }
    }

    private func clamped(_ value: CGFloat, lowerBound: CGFloat, upperBound: CGFloat) -> CGFloat {
        min(max(value, lowerBound), upperBound)
    }

    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        messageText = ""

        Task {
            await backend.refreshDashboard()
        }
    }
}

// MARK: - Mentee Character + Chat Bubble

/// A walking mentee character — visually distinct from the mentor (purple tint, offset start).
/// Represents a person the current user is mentoring in the social hub.
struct MenteeCharacterView: View {
    @ObservedObject var backend: HabitBackendStore
    @State private var walker = WalkerState()
    @State private var chatOpen = false
    @State private var chatShown = false
    @State private var chatAnimationTask: Task<Void, Never>? = nil
    @State private var hasAttention = false

    private let characterHeight: CGFloat = 130
    private let videoAspect: CGFloat = 1080 / 1920

    private var mentee: AccountabilityDashboard.MenteeSummary {
        if let real = backend.dashboard?.mentorDashboard.mentees.first {
            return real
        }
        // Fallback shown in DEBUG / before dashboard loads
        return AccountabilityDashboard.MenteeSummary(
            matchId: 0,
            userId: 0,
            displayName: "Alex",
            missedHabitsToday: 2,
            weeklyConsistencyPercent: 68,
            suggestedAction: "Send a quick check-in — they've missed 2 habits today."
        )
    }

    private let bubbleHeight: CGFloat = 252
    private let bubbleWidth: CGFloat = 260
    private let bubbleGap: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let charWidth = characterHeight * videoAspect
            let travelDistance = max(geo.size.width - charWidth, 0)
            let charX = walker.positionProgress * travelDistance
            let characterHeadX = charX + charWidth / 2
            let visibleCharTop = characterHeight * 0.85

            // Jazz — the orange lil-agent character
            LoopingVideoView(videoName: "walk-jazz-01", isPlaying: walker.isWalking)
                .frame(width: charWidth, height: characterHeight)
                .scaleEffect(x: walker.goingRight ? 1 : -1, y: 1, anchor: .center)
            .position(
                x: charX + charWidth / 2,
                y: geo.size.height - characterHeight / 2 + characterHeight * 0.15
            )
            .onTapGesture { toggleChat() }

            // Attention badge when mentee missed habits today
            if hasAttention && !chatOpen {
                Circle()
                    .fill(.orange)
                    .frame(width: 14, height: 14)
                    .overlay(
                        Image(systemName: "exclamationmark")
                            .font(.system(size: 8, weight: .black))
                            .foregroundStyle(.white)
                    )
                    .position(
                        x: charX + charWidth - 4,
                        y: geo.size.height - visibleCharTop - 4
                    )
            }

            // Chat bubble anchored above the character's head
            if chatOpen {
                let bubbleY = geo.size.height - visibleCharTop - bubbleGap - bubbleHeight / 2
                let clampedX = clamped(characterHeadX, lowerBound: bubbleWidth / 2 + 8, upperBound: geo.size.width - bubbleWidth / 2 - 8)
                let anchorX = (characterHeadX - (clampedX - bubbleWidth / 2)) / bubbleWidth
                let scaleAnchor = UnitPoint(x: clamped(anchorX, lowerBound: 0, upperBound: 1), y: 1)

                MenteeChatBubble(mentee: mentee, onSend: sendMessage, onClose: closeChat)
                    .frame(width: bubbleWidth, height: bubbleHeight)
                    .scaleEffect(chatShown ? 1 : 0.05, anchor: scaleAnchor)
                    .opacity(chatShown ? 1 : 0)
                    .position(x: clampedX, y: bubbleY)
                    .animation(.spring(response: 0.35, dampingFraction: 0.78), value: chatShown)
                    .zIndex(10)
            }

            Color.clear
                .onAppear {
                    // Start mentee on the right side so they walk toward the mentor
                    walker.positionProgress = 0.7
                    walker.goingRight = false
                    walker.travelDistance = travelDistance
                    walker.start()
                    hasAttention = mentee.missedHabitsToday > 0
                }
                .onChange(of: geo.size.width) { _, _ in
                    walker.travelDistance = travelDistance
                }
                .onChange(of: mentee.missedHabitsToday) { _, new in
                    if !chatOpen { hasAttention = new > 0 }
                }
        }
        .frame(height: chatOpen ? characterHeight + bubbleHeight + bubbleGap : characterHeight)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: chatOpen)
    }

    private func toggleChat() { chatOpen ? closeChat() : openChat() }

    private func openChat() {
        chatAnimationTask?.cancel()
        hasAttention = false
        chatShown = false
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { chatOpen = true }
        chatAnimationTask = Task {
            await Task.yield()
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) { chatShown = true }
            }
        }
    }

    private func closeChat() {
        chatAnimationTask?.cancel()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) { chatShown = false }
        chatAnimationTask = Task {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { chatOpen = false }
            }
        }
    }

    private func sendMessage(_ text: String) {
        let matchId = backend.dashboard?.mentorDashboard.mentees.first?.matchId ?? mentee.matchId
        Task { await backend.sendMenteeMessage(matchId: matchId, message: text) }
    }

    private func clamped(_ value: CGFloat, lowerBound: CGFloat, upperBound: CGFloat) -> CGFloat {
        min(max(value, lowerBound), upperBound)
    }
}

private struct MenteeChatBubble: View {
    let mentee: AccountabilityDashboard.MenteeSummary
    let onSend: (String) -> Void
    let onClose: () -> Void

    @State private var messageText = ""
    @State private var isSending = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Title bar — orange accent to match Jazz character
            HStack {
                Circle()
                    .fill(.orange)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(mentee.displayName)
                        .font(.system(size: 13, weight: .semibold))
                    Text("Your mentee")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(titleBarColor)

            Divider()

            // Mentee stats
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "chart.bar.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 12))
                    Text("Weekly consistency")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(mentee.weeklyConsistencyPercent)%")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(consistencyColor)
                }

                HStack {
                    Image(systemName: mentee.missedHabitsToday > 0 ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(mentee.missedHabitsToday > 0 ? Color.orange : Color.green)
                        .font(.system(size: 12))
                    Text("Missed today")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(mentee.missedHabitsToday == 0
                         ? "All done!"
                         : "\(mentee.missedHabitsToday) habit\(mentee.missedHabitsToday == 1 ? "" : "s")")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(mentee.missedHabitsToday > 0 ? Color.orange : Color.green)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Label("Suggested action", systemImage: "lightbulb.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.orange)
                    Text(mentee.suggestedAction)
                        .font(.system(size: 11))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(colorScheme == .dark ? 0.15 : 0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .padding(12)

            Divider()

            // Input row
            HStack(spacing: 8) {
                TextField("Cheer them up...", text: $messageText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .disabled(isSending)
                    .onSubmit { submitMessage() }

                Button(action: submitMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(
                            messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending
                                ? Color.secondary : Color.orange
                        )
                }
                .buttonStyle(.plain)
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(bubbleBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.18), radius: 16, y: 6)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    Color.orange.opacity(colorScheme == .dark ? 0.3 : 0.2),
                    lineWidth: 0.5
                )
        )
    }

    private func submitMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        isSending = true
        messageText = ""
        onSend(text)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { isSending = false }
    }

    private var consistencyColor: Color {
        mentee.weeklyConsistencyPercent >= 70 ? .green
            : mentee.weeklyConsistencyPercent >= 40 ? .orange
            : .red
    }

    private var titleBarColor: Color {
        colorScheme == .dark
            ? Color(red: 0.18, green: 0.14, blue: 0.11)
            : Color(red: 1.0, green: 0.97, blue: 0.94)
    }

    private var bubbleBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.14, green: 0.11, blue: 0.09)
            : Color.white
    }
}

// MARK: - Chat Bubble View

private struct MentorChatBubble: View {
    let mentorName: String
    let messages: [AccountabilityDashboard.Message]
    @Binding var messageText: String
    let onSend: () -> Void
    let onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Title bar — green theme
            HStack {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(mentorName)
                        .font(.system(size: 13, weight: .semibold))
                    Text("Your mentor")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(titleBarColor)

            Divider()

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if messages.isEmpty {
                            Text("Say hi to your mentor!")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                        }

                        ForEach(messages) { msg in
                            ChatMessageRow(message: msg)
                                .id(msg.id)
                        }
                    }
                    .padding(10)
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Input row
            HStack(spacing: 8) {
                TextField("Message...", text: $messageText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit(onSend)

                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(
                            messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? Color.secondary : Color.green
                        )
                }
                .buttonStyle(.plain)
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(bubbleBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.18), radius: 16, y: 6)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    Color.green.opacity(colorScheme == .dark ? 0.3 : 0.2),
                    lineWidth: 0.5
                )
        )
    }

    private var titleBarColor: Color {
        colorScheme == .dark
            ? Color(red: 0.11, green: 0.15, blue: 0.12)
            : Color(red: 0.94, green: 0.98, blue: 0.95)
    }

    private var bubbleBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.09, green: 0.12, blue: 0.10)
            : Color.white
    }
}

private struct ChatMessageRow: View {
    let message: AccountabilityDashboard.Message
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(message.senderName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)

                Text(message.message)
                    .font(.system(size: 12))
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

            Spacer(minLength: 40)
        }
    }

    private var messageBubbleColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color(red: 0.93, green: 0.93, blue: 0.95)
    }
}

// MARK: - Speech Bubble Nudge

private struct SpeechBubbleNudge: View {
    let text: String
    let width: CGFloat
    let tailAnchorX: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(colorScheme == .dark ? .white : .black)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(width: width)
                .background(backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(strokeColor, lineWidth: 0.5)
                )

            HStack(spacing: 0) {
                Spacer()
                    .frame(width: tailOffset)

                Triangle()
                    .fill(backgroundColor)
                    .frame(width: 12, height: 7)

                Spacer(minLength: 0)
            }
            .frame(width: width, alignment: .leading)
        }
    }

    private var backgroundColor: Color {
        colorScheme == .dark
            ? Color(red: 0.18, green: 0.19, blue: 0.22)
            : Color.white
    }

    private var strokeColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.12)
            : Color.black.opacity(0.08)
    }

    private var tailOffset: CGFloat {
        max(0, min(width - 12, width * tailAnchorX - 6))
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Walk State Machine

@Observable
class WalkerState {
    var positionProgress: CGFloat = 0.3
    var goingRight = true
    var isWalking = false
    var travelDistance: CGFloat = 500

    // Video timing (from lil-agents frame analysis for Bruce)
    private let videoDuration: CFTimeInterval = 10.0
    private let accelStart: CFTimeInterval = 3.0
    private let fullSpeedStart: CFTimeInterval = 3.75
    private let decelStart: CFTimeInterval = 8.0
    private let walkStop: CFTimeInterval = 8.5

    private var walkStartTime: CFTimeInterval = 0
    private var walkStartPos: CGFloat = 0
    private var walkEndPos: CGFloat = 0
    private var frameTimer: Timer?

    func start() {
        enterPause()
    }

    private func enterPause() {
        isWalking = false
        let delay = Double.random(in: 3.0...8.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.startWalk()
        }
    }

    private func startWalk() {
        if positionProgress > 0.85 {
            goingRight = false
        } else if positionProgress < 0.15 {
            goingRight = true
        } else {
            goingRight = Bool.random()
        }

        walkStartPos = positionProgress

        let referenceWidth: CGFloat = 500
        let walkPixels = CGFloat.random(in: 0.25...0.5) * referenceWidth
        let walkAmount = travelDistance > 0 ? walkPixels / travelDistance : 0.3

        if goingRight {
            walkEndPos = min(walkStartPos + walkAmount, 1.0)
        } else {
            walkEndPos = max(walkStartPos - walkAmount, 0.0)
        }

        isWalking = true
        walkStartTime = CACurrentMediaTime()

        frameTimer?.invalidate()
        frameTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        let elapsed = CACurrentMediaTime() - walkStartTime

        if elapsed >= videoDuration {
            frameTimer?.invalidate()
            frameTimer = nil
            positionProgress = walkEndPos
            enterPause()
            return
        }

        let walkNorm = movementPosition(at: elapsed)
        positionProgress = walkStartPos + (walkEndPos - walkStartPos) * walkNorm
    }

    private func movementPosition(at videoTime: CFTimeInterval) -> CGFloat {
        let dIn = fullSpeedStart - accelStart
        let dLin = decelStart - fullSpeedStart
        let dOut = walkStop - decelStart

        let v = 1.0 / (dIn / 2.0 + dLin + dOut / 2.0)

        if videoTime <= accelStart {
            return 0.0
        } else if videoTime <= fullSpeedStart {
            let t = videoTime - accelStart
            return CGFloat(v * t * t / (2.0 * dIn))
        } else if videoTime <= decelStart {
            let easeInDist = v * dIn / 2.0
            let t = videoTime - fullSpeedStart
            return CGFloat(easeInDist + v * t)
        } else if videoTime <= walkStop {
            let easeInDist = v * dIn / 2.0
            let linearDist = v * dLin
            let t = videoTime - decelStart
            return CGFloat(easeInDist + linearDist + v * (t - t * t / (2.0 * dOut)))
        } else {
            return 1.0
        }
    }
}

// MARK: - Looping Video Player (NSViewRepresentable)

#if os(macOS)
private struct LoopingVideoView: NSViewRepresentable {
    let videoName: String
    let isPlaying: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor

        guard let url = Bundle.main.url(forResource: videoName, withExtension: "mov") else {
            return view
        }

        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        let player = AVQueuePlayer(playerItem: item)
        let looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(asset: asset))

        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = NSColor.clear.cgColor
        view.layer?.addSublayer(playerLayer)

        context.coordinator.player = player
        context.coordinator.looper = looper
        context.coordinator.playerLayer = playerLayer

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.playerLayer?.frame = nsView.bounds

        if isPlaying {
            context.coordinator.player?.play()
        } else {
            context.coordinator.player?.pause()
            context.coordinator.player?.seek(to: .zero)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        var player: AVQueuePlayer?
        var looper: AVPlayerLooper?
        var playerLayer: AVPlayerLayer?
    }
}
#endif

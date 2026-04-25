import SwiftUI

/// One-time profile-setup screen shown immediately after a fresh
/// Sign in with Apple sign-up — Apple's identity token only includes the
/// user's email + (optionally) name once, so this is the user's first
/// chance to pick the public handle they want on the leaderboard and
/// the avatar that shows up next to it.
///
/// Presented as a full-screen overlay above `ContentViewScaffold` while
/// `HabitBackendStore.requiresProfileSetup == true`. On submit success
/// the flag clears and the user falls through to normal onboarding.
struct AppleProfileSetupView: View {
    @ObservedObject var backend: HabitBackendStore
    let onComplete: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    @State private var username: String = ""
    @State private var selectedAvatarID = AvatarChoice.options.randomElement()?.id ?? AvatarChoice.options[0].id
    @State private var availability: AvailabilityState = .untouched
    @State private var lastCheckedUsername: String = ""
    @State private var checkTask: Task<Void, Never>?
    @State private var isSubmitting = false
    @FocusState private var usernameFocused: Bool

    private enum AvailabilityState {
        case untouched
        case checking
        case available
        case taken
        case invalid
    }

    private var trimmedUsername: String {
        username.trimmingCharacters(in: .whitespaces)
    }

    private var isUsernameFormatValid: Bool {
        let pattern = "^[A-Za-z0-9_]{3,30}$"
        return trimmedUsername.range(of: pattern, options: .regularExpression) != nil
    }

    private var canSubmit: Bool {
        isUsernameFormatValid && availability == .available && !isSubmitting
    }

    private var selectedAvatar: AvatarChoice {
        AvatarChoice.options.first { $0.id == selectedAvatarID } ?? AvatarChoice.options[0]
    }

    var body: some View {
        ZStack {
            MinimalBackground()
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 32) {
                    Spacer(minLength: 60)

                    header

                    avatarPreview

                    usernameField

                    avatarGrid

                    continueButton

                    Spacer(minLength: 60)
                }
                .frame(maxWidth: 540)
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear { usernameFocused = true }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(CleanShotTheme.accent)

            Text("Welcome to Forma.")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)

            Text("Pick a username and a character — these show up on the leaderboard.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var avatarPreview: some View {
        VStack(spacing: 10) {
            AsyncImage(url: URL(string: selectedAvatar.url)) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 120, height: 120)
            .background(
                Circle().fill(CleanShotTheme.accent.opacity(colorScheme == .dark ? 0.18 : 0.12))
            )
            .overlay(
                Circle().strokeBorder(CleanShotTheme.accent.opacity(0.45), lineWidth: 2)
            )
            .clipShape(Circle())
            Text(trimmedUsername.isEmpty ? "your name here" : "@\(trimmedUsername.lowercased())")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(trimmedUsername.isEmpty ? .tertiary : .primary)
                .animation(.smooth(duration: 0.18), value: trimmedUsername)
        }
    }

    private var usernameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("USERNAME")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .kerning(0.4)

            HStack(spacing: 10) {
                Text("@")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField("e.g. jashan", text: $username)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .medium))
                    .focused($usernameFocused)
                    .autocorrectionDisabled(true)
                    .onSubmit(submit)
                    .onChange(of: username) { _, _ in
                        scheduleAvailabilityCheck()
                    }
                availabilityBadge
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )

            Text(helperText)
                .font(.system(size: 12))
                .foregroundStyle(helperColor)
                .animation(.smooth(duration: 0.16), value: availability)
                .animation(.smooth(duration: 0.16), value: isUsernameFormatValid)
        }
    }

    @ViewBuilder
    private var availabilityBadge: some View {
        switch availability {
        case .checking:
            ProgressView().controlSize(.small)
        case .available:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.green)
                .transition(.scale.combined(with: .opacity))
        case .taken, .invalid:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(CleanShotTheme.danger)
                .transition(.scale.combined(with: .opacity))
        case .untouched:
            EmptyView()
        }
    }

    private var avatarGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CHARACTER")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .kerning(0.4)
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5),
                spacing: 8
            ) {
                ForEach(AvatarChoice.options) { avatar in
                    AvatarChoiceButton(
                        avatar: avatar,
                        isSelected: avatar.id == selectedAvatarID,
                        action: { selectedAvatarID = avatar.id }
                    )
                }
            }
        }
    }

    private var continueButton: some View {
        VStack(spacing: 10) {
            Button(action: submit) {
                HStack(spacing: 8) {
                    if isSubmitting {
                        ProgressView().controlSize(.small).tint(.white)
                    }
                    Text("Continue →")
                        .font(.system(size: 15, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
            }
            .buttonStyle(PrimaryCapsuleButtonStyle())
            .disabled(!canSubmit)
            .opacity(canSubmit ? 1 : 0.6)
            .animation(.smooth(duration: 0.16), value: canSubmit)

            if let err = backend.errorMessage {
                Text(err)
                    .font(.system(size: 12))
                    .foregroundStyle(CleanShotTheme.danger)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Helpers

    private var borderColor: Color {
        switch availability {
        case .available: return Color.green.opacity(0.7)
        case .taken, .invalid: return CleanShotTheme.danger.opacity(0.7)
        case .checking, .untouched: return Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.10)
        }
    }

    private var helperColor: Color {
        switch availability {
        case .available: return Color.green
        case .taken, .invalid: return CleanShotTheme.danger
        default: return .secondary
        }
    }

    private var helperText: String {
        if !isUsernameFormatValid && !trimmedUsername.isEmpty {
            return "Use 3-30 letters, numbers, or underscores."
        }
        switch availability {
        case .checking:    return "Checking availability…"
        case .available:   return "@\(trimmedUsername.lowercased()) is available."
        case .taken:       return "Sorry, that's taken — try another."
        case .invalid:     return "Use 3-30 letters, numbers, or underscores."
        case .untouched:   return "Letters, numbers, or underscores. 3-30 characters."
        }
    }

    private func scheduleAvailabilityCheck() {
        checkTask?.cancel()
        backend.errorMessage = nil
        guard !trimmedUsername.isEmpty else {
            availability = .untouched
            return
        }
        guard isUsernameFormatValid else {
            availability = .invalid
            return
        }
        availability = .checking
        let candidate = trimmedUsername
        checkTask = Task {
            // Debounce — let typing settle before hitting the network.
            try? await Task.sleep(nanoseconds: 350_000_000)
            if Task.isCancelled { return }
            let available = await backend.isUsernameAvailable(candidate)
            if Task.isCancelled { return }
            await MainActor.run {
                guard candidate == trimmedUsername else { return }
                availability = available ? .available : .taken
                lastCheckedUsername = candidate
            }
        }
    }

    private func submit() {
        guard canSubmit else { return }
        isSubmitting = true
        let chosenName = trimmedUsername
        let chosenAvatar = selectedAvatar.url
        Task {
            let success = await backend.setupAppleProfile(
                username: chosenName,
                avatarURL: chosenAvatar
            )
            await MainActor.run {
                isSubmitting = false
                if success {
                    onComplete()
                } else {
                    // Backend returned a 4xx (likely "username taken" if
                    // someone grabbed it between availability check and
                    // submit). Reset the badge so the inline copy
                    // matches.
                    availability = .taken
                }
            }
        }
    }
}

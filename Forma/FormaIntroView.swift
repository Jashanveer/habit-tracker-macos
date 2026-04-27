import SwiftUI

/// App-launch orchestrator. Owns the floating-pills background for the entire
/// cold-launch experience so the authenticated dashboard never bleeds through
/// during the intro. Runs the icon build, hands off to `AuthGateView` (whose
/// card slot receives the icon via matched geometry), then plays the
/// grid-cascade `FormaTransition` before dismissing to reveal the dashboard
/// underneath.
///
/// When the user submits the auth form, the cascade starts immediately and
/// acts as a loading cover: tiles fill the screen, hold while the request is
/// in flight, then fade out when the backend confirms authentication (or
/// reverse back to the auth card on failure).
struct FormaIntroView: View {
    @ObservedObject var backend: HabitBackendStore
    let onReady: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var phase: Phase = .intro
    @State private var buildStep: Int = 0
    @State private var iconSize: CGFloat = 110
    @State private var titleVisible = false
    @State private var didStart = false
    /// True while the cascade is acting as a loading cover for a pending
    /// sign-in/register request. Drives failure recovery when the sync ends
    /// without a successful authentication.
    @State private var pendingAuthSubmission = false
    /// Passed to `FormaTransition.readyToReveal`. Flips to true once the
    /// in-flight auth request has settled (success → dashboard, failure →
    /// back to the auth card). For the already-signed-in cold-launch path
    /// this is set true at the moment we enter `.cascade` so the cascade
    /// plays its original timeline uninterrupted.
    @State private var cascadeShouldReveal = false
    @Namespace private var loginNamespace

    private enum Phase {
        case intro     // icon is building, centered
        case auth      // AuthGateView visible, icon has flown into the card slot
        case cascade   // grid cascade covers the screen
        case done      // overlay removed
    }

    private var isVisible: Bool {
        if phase == .done { return !backend.isAuthenticated }
        return true
    }

    var body: some View {
        Group {
            if isVisible {
                content
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(phase != .done)
        .task {
            guard !didStart else { return }
            didStart = true
            await runIntro()
        }
        .onChange(of: backend.isAuthenticated) { _, isAuth in
            if isAuth {
                // Request succeeded — let the cascade fade out.
                if phase == .cascade {
                    cascadeShouldReveal = true
                } else if phase == .auth {
                    Task { await beginCascade() }
                }
            } else if phase == .done {
                resetToAuth()
            }
        }
        .onChange(of: backend.isSyncing) { wasSyncing, isSyncing in
            // Auth attempt failed: the request ended (isSyncing true → false)
            // while we're covering the screen but still unauthenticated. Let
            // the cascade fade out so the auth card (with its error message)
            // is revealed underneath.
            guard wasSyncing, !isSyncing,
                  phase == .cascade,
                  pendingAuthSubmission,
                  !backend.isAuthenticated
            else { return }
            pendingAuthSubmission = false
            cascadeShouldReveal = true
        }
    }

    private func resetToAuth() {
        buildStep = 5
        titleVisible = true
        iconSize = 64
        pendingAuthSubmission = false
        cascadeShouldReveal = false
        withAnimation(.smooth(duration: 0.3)) {
            phase = .auth
        }
    }

    // MARK: - Content

    private var content: some View {
        ZStack {
            // Pills background — always on while the intro overlay is mounted.
            // It adapts to colorScheme internally and covers whatever sits below
            // (dashboard, onboarding) so nothing leaks through the intro.
            FloatingHabitBackground()
                .ignoresSafeArea()

            // Auth card appears only once we hand off; its internal appIcon
            // carries the matched-geometry counterpart to our centered icon.
            if phase == .auth || phase == .cascade {
                AuthGateView(
                    backend: backend,
                    iconNamespace: loginNamespace,
                    onAuthSubmit: handleAuthSubmit,
                    // Drop the cascade if Apple sign-in fails so the user
                    // returns to the auth card with the error visible
                    // instead of staring at the yellow/blue grid forever.
                    // Uses cascadeShouldReveal (the positive "ready to fade
                    // out" flag macOS exposes) — handleCascadeComplete then
                    // routes back to .auth because !backend.isAuthenticated.
                    onAuthFailed: { cascadeShouldReveal = true },
                    onAuthenticated: {}
                )
                .transition(.opacity)
            }

            // Blue radial glow behind the building icon — only during intro.
            if phase == .intro {
                RadialGradient(
                    colors: [Color.formaBlue.opacity(0.13), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: 260
                )
                .blur(radius: 40)
                .frame(width: 520, height: 520)
                .allowsHitTesting(false)
                .transition(.opacity)
            }

            // The Forma icon + wordmark. During .intro it lives centered; the
            // wordmark/tagline appear once the icon is fully built. In .auth
            // the icon flies into the card slot via matched geometry and the
            // brand column here hides.
            if phase == .intro {
                brandColumn
                    .transition(.opacity)
            }

            if phase == .cascade {
                FormaTransition(readyToReveal: cascadeShouldReveal) {
                    handleCascadeComplete()
                }
                .transition(.opacity)
            }
        }
    }

    /// Called when the cascade has fully faded out. Routes to `.done` on a
    /// successful auth (dashboard ready underneath) or back to `.auth` when
    /// the cascade was a loading cover for a request that failed.
    @MainActor
    private func handleCascadeComplete() {
        if backend.isAuthenticated {
            withAnimation(.easeOut(duration: 0.2)) {
                phase = .done
            }
            onReady()
        } else {
            pendingAuthSubmission = false
            cascadeShouldReveal = false
            withAnimation(.easeOut(duration: 0.2)) {
                phase = .auth
            }
        }
    }

    /// Triggered by `AuthGateView` the moment a sign-in / final-register
    /// request is about to fire. Drops the cascade over the screen so the
    /// user sees a cover instead of a spinner-on-card while the backend works.
    @MainActor
    private func handleAuthSubmit() {
        guard phase == .auth else { return }
        pendingAuthSubmission = true
        cascadeShouldReveal = false
        withAnimation(.smooth(duration: 0.25)) {
            phase = .cascade
        }
    }

    private var brandColumn: some View {
        VStack(spacing: 12) {
            FormaIconView(size: iconSize, buildStep: buildStep)
                .matchedGeometryEffect(id: "auth-app-icon", in: loginNamespace)
                .shadow(color: Color.formaBlue.opacity(0.4), radius: 30, y: 10)
                .animation(.spring(response: 0.6, dampingFraction: 0.82), value: iconSize)

            VStack(spacing: 4) {
                Text("Forma")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(wordmarkColor)

                Text("Form the habits that form you")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(taglineColor)
                    .textCase(.uppercase)
                    .kerning(1.2)
            }
            .opacity(titleVisible ? 1 : 0)
            .animation(.easeIn(duration: 0.5), value: titleVisible)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .allowsHitTesting(false)
    }

    // MARK: - Colors

    private var wordmarkColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.94) : Color.black.opacity(0.82)
    }

    private var taglineColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.48) : Color.black.opacity(0.44)
    }

    // MARK: - Timeline

    @MainActor
    private func runIntro() async {
        if reduceMotion {
            buildStep = 5
            titleVisible = true
            iconSize = 64
            if backend.isAuthenticated {
                await beginCascade()
            } else {
                withAnimation(.smooth(duration: 0.3)) {
                    phase = .auth
                }
            }
            return
        }

        try? await Task.sleep(nanoseconds: 250_000_000)
        buildStep = 1
        try? await Task.sleep(nanoseconds: 200_000_000)
        buildStep = 2
        try? await Task.sleep(nanoseconds: 250_000_000)
        buildStep = 3
        try? await Task.sleep(nanoseconds: 250_000_000)
        buildStep = 4
        try? await Task.sleep(nanoseconds: 300_000_000)
        buildStep = 5
        titleVisible = true

        try? await Task.sleep(nanoseconds: 550_000_000)

        if backend.isAuthenticated {
            // Already signed in — cascade directly into dashboard (or onboarding).
            await beginCascade()
            return
        }

        // Hand off to the auth card. The icon flies into the card slot via
        // matched geometry because both sides share id "auth-app-icon".
        withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
            iconSize = 64
            phase = .auth
        }
    }

    @MainActor
    private func beginCascade() async {
        // Already-authenticated path: the backend has a valid session, so the
        // cascade should play its full cascade-in → hold → fade timeline
        // without waiting. Clear any lingering submission flag so the failure
        // handler in onChange(isSyncing) doesn't misfire during this cascade.
        pendingAuthSubmission = false
        cascadeShouldReveal = true
        withAnimation(.smooth(duration: 0.3)) {
            phase = .cascade
        }
    }
}

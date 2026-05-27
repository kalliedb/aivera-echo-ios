import AVFoundation
import Speech
import SwiftUI
import UserNotifications

/// 3-page onboarding shown on first launch. Mirrors Android's OnboardingScreen.
/// Permission requests are contextual (button on page 2), not at app launch.
struct OnboardingView: View {

    let onComplete: () -> Void

    @State private var page = 0
    @State private var permissionsRequested = false

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                pageWelcome.tag(0)
                pagePermissions.tag(1)
                pagePrivacy.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            HStack {
                if page < 2 {
                    Button("Skip") { onComplete() }
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        withAnimation { page = min(page + 1, 2) }
                    } label: {
                        Text("Next")
                            .font(.body.weight(.semibold))
                            .padding(.horizontal, 32)
                            .padding(.vertical, 12)
                            .background(LinearGradient(
                                colors: [.echoAccent, .echoPurple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                } else {
                    Spacer()
                    Button {
                        onComplete()
                    } label: {
                        Text("Get started")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(LinearGradient(
                                colors: [.echoAccent, .echoPurple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .background(Color.echoBg.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    // MARK: - Pages

    private var pageWelcome: some View {
        OnboardingPage(
            icon: "mic.fill",
            title: "Speak your reminders",
            body: "Tap the mic and just say it — \u{201C}remind me to call Sam at 5pm.\u{201D} Echo turns your voice into a reminder, transcribed offline on your phone."
        )
    }

    private var pagePermissions: some View {
        OnboardingPage(
            icon: "bell.badge.fill",
            title: "A couple of permissions",
            body: """
            Microphone — so we can hear what you want to be reminded about.
            Notifications — so we can alert you when a reminder is due.
            Voice never leaves your device for transcription.
            """,
            actionLabel: permissionsRequested
                ? "Permissions requested"
                : "Enable microphone & notifications",
            actionDisabled: permissionsRequested,
            action: { Task { await requestPermissions() } }
        )
    }

    private var pagePrivacy: some View {
        OnboardingPage(
            icon: "lock.fill",
            title: "Private by default",
            body: "Your reminders live on this device. Optional cloud sync (which you turn on in Settings) backs them up and keeps them in step across your devices."
        )
    }

    // MARK: - Permissions

    @MainActor
    private func requestPermissions() async {
        permissionsRequested = true

        // Microphone
        _ = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            AVAudioSession.sharedInstance().requestRecordPermission { cont.resume(returning: $0) }
        }
        // Speech recognition (used by SpeechRecognizer in the home screen)
        _ = await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        // Notifications
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
    }
}

private struct OnboardingPage: View {
    let icon: String
    let title: String
    let body: String
    var actionLabel: String?     = nil
    var actionDisabled: Bool     = false
    var action: (() -> Void)?    = nil

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.echoPurpleContainer.opacity(0.3), .echoPurple.opacity(0.15)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 120, height: 120)
                Image(systemName: icon)
                    .font(.system(size: 56))
                    .foregroundStyle(Color.echoAccent)
            }

            Text(title)
                .font(.title.weight(.semibold))
                .multilineTextAlignment(.center)

            Text(body)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)

            if let actionLabel, let action {
                Button(action: action) {
                    Text(actionLabel)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.echoAccent.opacity(0.15))
                        .foregroundStyle(Color.echoAccent)
                        .clipShape(Capsule())
                }
                .disabled(actionDisabled)
                .opacity(actionDisabled ? 0.6 : 1.0)
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 24)
    }
}

#Preview {
    OnboardingView(onComplete: {})
}

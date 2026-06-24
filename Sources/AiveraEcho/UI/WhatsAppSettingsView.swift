import SwiftUI

/// FR-INT-001 — Settings → WhatsApp delivery (iOS port of Android's
/// WhatsAppSettingsScreen.kt). Four-state machine:
///
///   notEnabled       → marketing card + "Enable WhatsApp delivery" CTA
///   enteringPhone    → phone input + "Send code"
///   waitingForCode   → 6-digit OTP entry + "Resend" / "Change number"
///   verified         → confirmation + delivery toggle + "Change number"
///
/// The verify/confirm Edge Functions require a user JWT, so this view
/// short-circuits to a sign-in prompt when the session is nil.
struct WhatsAppSettingsView: View {

    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var sessionStore: SessionStore
    @Environment(\.dismiss) private var dismiss

    enum UiState: Equatable {
        case notEnabled
        case loading
        case enteringPhone(error: String? = nil)
        case waitingForCode(maskedPhone: String, phoneE164: String, error: String? = nil)
        case verified(maskedPhone: String)
    }

    @State private var ui: UiState = .notEnabled
    @State private var phoneInput: String = "+27"
    @State private var codeInput: String = ""
    @FocusState private var phoneFocused: Bool
    @FocusState private var codeFocused: Bool

    /// Called when the user wants to leave the screen via "Done".
    var onDone: () -> Void = {}

    var body: some View {
        NavigationStack {
            Form {
                if sessionStore.session == nil {
                    signInSection
                } else {
                    contentSections
                }
            }
            .navigationTitle("WhatsApp delivery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onDone(); dismiss() }
                }
            }
        }
    }

    // MARK: - Sections

    private var signInSection: some View {
        Section {
            Text("Sign in to enable WhatsApp delivery")
                .font(.headline)
            Text("WhatsApp delivery is tied to your Echo account so we can route reminders to the right number.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } footer: {
            Text("Open Settings → Sync to sign in.")
        }
    }

    @ViewBuilder
    private var contentSections: some View {
        switch ui {
        case .loading:
            Section { HStack { ProgressView(); Text("Working…").foregroundStyle(.secondary) } }

        case .notEnabled:
            notEnabledSection

        case let .enteringPhone(error):
            phoneEntrySection(error: error)

        case let .waitingForCode(maskedPhone, phoneE164, error):
            codeEntrySection(maskedPhone: maskedPhone, phoneE164: phoneE164, error: error)

        case let .verified(maskedPhone):
            verifiedSections(maskedPhone: maskedPhone)
        }
    }

    private var notEnabledSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Get reminders on WhatsApp").font(.headline)
                Text("When a reminder fires, we'll also send it as a WhatsApp message. Tap Done in WhatsApp to close it out without unlocking your phone.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)

            Button {
                ui = .enteringPhone(error: nil)
                phoneFocused = true
            } label: {
                Text("Enable WhatsApp delivery")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        } footer: {
            Text("We send only what you opt in for. Reply STOP to any Echo WhatsApp message to unsubscribe immediately.")
        }
    }

    private func phoneEntrySection(error: String?) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Enter your WhatsApp number").font(.headline)
                Text("Use international format with the + sign, e.g. +27 64 534 1659. We'll send a 6-digit code to verify you own this number.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)

            TextField("Phone number", text: $phoneInput)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .focused($phoneFocused)
                .onChange(of: phoneInput) { _, newValue in
                    phoneInput = newValue.filter { $0.isNumber || $0 == "+" }
                }

            if let error {
                Text(error).font(.footnote).foregroundStyle(.red)
            }

            HStack(spacing: 12) {
                Button("Cancel", role: .cancel) {
                    ui = .notEnabled
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.bordered)

                Button("Send code") {
                    Task { await requestCode() }
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func codeEntrySection(maskedPhone: String, phoneE164: String, error: String?) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Enter the code we sent you").font(.headline)
                Text("Sent to \(maskedPhone). Open WhatsApp, tap Copy code on the Aivera Echo message, then paste it here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)

            TextField("6-digit code", text: $codeInput)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($codeFocused)
                .onAppear { codeFocused = true }
                .onChange(of: codeInput) { _, newValue in
                    codeInput = String(newValue.filter { $0.isNumber }.prefix(6))
                }

            if let error {
                Text(error).font(.footnote).foregroundStyle(.red)
            }

            Button("Verify") {
                Task { await submitCode() }
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.borderedProminent)
            .disabled(codeInput.count != 6)

            HStack {
                Button("Resend code") {
                    Task { await requestCode(prefilled: phoneE164) }
                }
                Spacer()
                Button("Change number") {
                    ui = .enteringPhone(error: nil)
                    phoneFocused = true
                }
            }
            .font(.subheadline)
        }
    }

    private func verifiedSections(maskedPhone: String) -> some View {
        Group {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("WhatsApp delivery is set up").font(.headline)
                    Text("We'll deliver reminders to \(maskedPhone) via WhatsApp when this is on.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                Toggle("Send reminders via WhatsApp",
                       isOn: settingsStore.binding(\.whatsappDeliveryEnabled))
            } footer: {
                Text("Reply STOP to any Echo WhatsApp message to opt out instantly. You can re-enable here any time.")
            }

            Section {
                Button("Change number") {
                    ui = .enteringPhone(error: nil)
                    phoneFocused = true
                }
            }
        }
    }

    // MARK: - Actions

    private func requestCode(prefilled: String? = nil) async {
        let raw = Self.normalizePhoneE164(prefilled ?? phoneInput)
        // E.164: leading +, country code (1-9), 7–15 total digits.
        let pattern = #"^\+[1-9]\d{7,14}$"#
        guard raw.range(of: pattern, options: .regularExpression) != nil else {
            ui = .enteringPhone(error: "Use international format with the + sign, e.g. +27 64 534 1659")
            return
        }
        ui = .loading
        switch await WhatsAppClient.verify(phoneE164: raw) {
        case let .sent(masked, expires):
            codeInput = ""
            ui = .waitingForCode(maskedPhone: masked, phoneE164: raw, error: nil)
            codeFocused = true
            _ = expires // could surface a countdown in M3.8d
        case let .failed(message):
            ui = .enteringPhone(error: message)
        case .notSignedIn:
            ui = .enteringPhone(error: "Sign in first to enable WhatsApp delivery")
        }
    }

    /// Normalise a user-typed phone string into E.164. The UI prefills "+27",
    /// and SA users routinely append their *local-format* number which retains
    /// a leading 0 (e.g. typing "0794915947" after "+27" yields "+270794915947").
    /// That looks valid but isn't — Meta then sees a non-existent number. This
    /// strips a stray 0 sitting immediately after the country code.
    static func normalizePhoneE164(_ raw: String) -> String {
        let stripped = raw.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: #"[\s\-()]"#, with: "", options: .regularExpression)
        guard let regex = try? NSRegularExpression(pattern: #"^(\+\d{1,3})0(\d+)$"#),
              let match = regex.firstMatch(in: stripped, range: NSRange(stripped.startIndex..., in: stripped)),
              match.numberOfRanges >= 3,
              let cc = Range(match.range(at: 1), in: stripped),
              let rest = Range(match.range(at: 2), in: stripped)
        else { return stripped }
        return String(stripped[cc]) + String(stripped[rest])
    }

    private func submitCode() async {
        guard case let .waitingForCode(masked, phone, _) = ui else { return }
        let code = codeInput.trimmingCharacters(in: .whitespaces)
        guard code.count == 6 else {
            ui = .waitingForCode(maskedPhone: masked, phoneE164: phone, error: "Enter the 6-digit code")
            return
        }
        ui = .loading
        switch await WhatsAppClient.confirm(code: code) {
        case let .verified(verifiedPhone):
            ui = .verified(maskedPhone: verifiedPhone)
            // Flip the local toggle on by default once verified — matches
            // user expectation that "I just verified" means "start sending".
            settingsStore.settings.whatsappDeliveryEnabled = true
        case .codeExpired:
            ui = .waitingForCode(maskedPhone: masked, phoneE164: phone, error: "Code expired — request a new one")
        case let .failed(message):
            ui = .waitingForCode(maskedPhone: masked, phoneE164: phone, error: message)
        case .notSignedIn:
            ui = .enteringPhone(error: "Sign in first to enable WhatsApp delivery")
        }
    }
}

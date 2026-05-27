import SwiftUI

/// Settings sheet — mirrors Android's SettingsScreen.kt section-by-section.
struct SettingsView: View {

    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var repository: ReminderRepository
    @EnvironmentObject private var entitlementStore: EntitlementStore
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    @State private var confirmDeleteData = false
    @State private var confirmDeleteAccount = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: settingsStore.binding(\.theme)) {
                        ForEach(ThemeMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Notifications") {
                    Toggle("Sound",      isOn: settingsStore.binding(\.soundEnabled))
                    Toggle("Vibration",  isOn: settingsStore.binding(\.vibrationEnabled))
                    Toggle("Quiet hours (10pm–7am)",
                           isOn: settingsStore.binding(\.quietHoursEnabled))
                }

                Section("Reminders") {
                    Toggle("Location reminders",
                           isOn: settingsStore.binding(\.locationEnabled))
                    Picker("Keep audio for",
                           selection: settingsStore.binding(\.audioRetentionDays)) {
                        Text("7 days").tag(7)
                        Text("14 days").tag(14)
                        Text("30 days").tag(30)
                    }
                    .pickerStyle(.menu)
                }

                Section("Sync") {
                    Toggle("Cloud sync",
                           isOn: settingsStore.binding(\.cloudSyncEnabled))
                    if let s = sessionStore.session {
                        LabeledContent("Signed in as") {
                            Text(s.email).foregroundStyle(.secondary).lineLimit(1)
                        }
                        LabeledContent("Plan") {
                            Text(entitlementStore.planLabel)
                                .foregroundStyle(entitlementStore.entitled
                                                 ? Color.echoAccent
                                                 : .secondary)
                        }
                    }
                }

                Section("Privacy") {
                    Button(role: .destructive) { confirmDeleteData = true } label: {
                        Label("Delete my data", systemImage: "trash")
                    }
                    if sessionStore.session != nil {
                        Button(role: .destructive) { confirmDeleteAccount = true } label: {
                            Label("Delete account", systemImage: "person.crop.circle.badge.minus")
                        }
                    }
                }

                Section("About") {
                    Button { open("/privacy") } label: { legalRow("Privacy Policy") }
                    Button { open("/terms") }   label: { legalRow("Terms of Service") }
                    Button { open("/refund") }  label: { legalRow("Refund Policy") }
                    Button { open("/support") } label: { legalRow("Support") }
                    Button { open("") }         label: { legalRow("About Aivera Echo") }
                }

                Section {
                    Text("Aivera Echo · 1.0.0")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                } footer: {
                    Text("Built by Aivera Solutions in South Africa.")
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Delete my data?",
                                isPresented: $confirmDeleteData,
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    Task { await deleteMyData() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes all reminders and saved audio on this device. This can't be undone.")
            }
            .confirmationDialog("Delete account?",
                                isPresented: $confirmDeleteAccount,
                                titleVisibility: .visible) {
                Button("Delete account", role: .destructive) {
                    Task { await deleteAccount() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Signs you out and deletes your local data. To remove your cloud account entirely, use the account-deletion page on aivera.solutions.")
            }
        }
    }

    @ViewBuilder
    private func legalRow(_ label: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.primary)
            Spacer()
            Image(systemName: "arrow.up.right.square")
                .foregroundStyle(.tertiary)
                .font(.caption)
        }
    }

    private func open(_ path: String) {
        guard let url = URL(string: "https://www.aivera.solutions/echo\(path)") else { return }
        openURL(url)
    }

    // MARK: - Destructive actions

    /// Wipe local reminders + audio + scheduled notifications + geofences.
    /// Server data is left intact (sync push wouldn't fire if user is offline /
    /// signed out anyway). For full server-side deletion, the user uses the
    /// /echo/delete-account page on the website.
    private func deleteMyData() async {
        await repository.wipeAll()

        // Audio folder
        if let docs = try? FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask,
            appropriateFor: nil, create: false
        ) {
            try? FileManager.default.removeItem(at: docs.appendingPathComponent("audio"))
        }
    }

    private func deleteAccount() async {
        await deleteMyData()
        await sessionStore.signOut()
    }
}

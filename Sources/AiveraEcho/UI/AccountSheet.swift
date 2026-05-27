import SwiftUI

/// Sign-in / sign-up / signed-in view. Mirrors Android's AccountScreen.kt.
struct AccountSheet: View {

    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var syncEngine: SyncEngine
    @EnvironmentObject private var entitlementStore: EntitlementStore
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false

    var body: some View {
        NavigationStack {
            Form {
                if !SupabaseConfig.isConfigured {
                    Section {
                        Label("Cloud sync isn't configured in this build",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                } else if let session = sessionStore.session {
                    signedInSections(session: session)
                } else {
                    signInSections
                }
            }
            .navigationTitle("Account & sync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func signedInSections(session: AppSession) -> some View {
        Section("Signed in") {
            Label(session.email, systemImage: "person.crop.circle")
            LabeledContent("Plan") {
                HStack(spacing: 6) {
                    if entitlementStore.entitled {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(Color.echoAccent)
                    }
                    Text(entitlementStore.planLabel)
                        .foregroundStyle(entitlementStore.entitled
                                         ? Color.echoAccent
                                         : .secondary)
                }
            }
        }

        Section("Sync") {
            Button {
                Task { await syncEngine.syncNow() }
            } label: {
                HStack {
                    if syncEngine.isSyncing {
                        ProgressView().controlSize(.small)
                        Text("Syncing…")
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Sync now")
                    }
                }
            }
            .disabled(syncEngine.isSyncing)

            if let last = syncEngine.lastSyncedAt {
                LabeledContent("Last synced") {
                    Text(last, style: .relative)
                        .foregroundStyle(.secondary)
                }
            }
            if let err = syncEngine.lastError {
                Text(err).foregroundStyle(.red).font(.footnote)
            }
        }

        Section {
            Button("Sign out", role: .destructive) {
                Task { await sessionStore.signOut() }
            }
            .disabled(sessionStore.isBusy)
        }
    }

    @ViewBuilder
    private var signInSections: some View {
        Section("Email") {
            TextField("you@example.com", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
        Section("Password") {
            SecureField("Password (min 6 chars)", text: $password)
                .textContentType(isSignUp ? .newPassword : .password)
        }

        Section {
            Button {
                Task { await primaryAction() }
            } label: {
                HStack {
                    if sessionStore.isBusy {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(isSignUp ? "Create account" : "Sign in").bold()
                    }
                }
            }
            .disabled(email.isEmpty || password.count < 6 || sessionStore.isBusy)
        }

        Section {
            Button(isSignUp
                   ? "Already have an account? Sign in"
                   : "Don't have an account? Sign up") {
                isSignUp.toggle()
                sessionStore.lastError = nil
                sessionStore.lastInfo = nil
            }
            .foregroundStyle(Color.echoAccent)
        }

        if let err = sessionStore.lastError {
            Section { Text(err).foregroundStyle(.red) }
        }
        if let info = sessionStore.lastInfo {
            Section { Text(info).foregroundStyle(Color.echoAccent) }
        }
    }

    private func primaryAction() async {
        if isSignUp {
            let immediate = await sessionStore.signUp(email: email, password: password)
            if immediate {
                await entitlementStore.refresh()
            } else {
                // Email-confirm flow: switch back to sign-in mode after the
                // "check your email" info message renders.
                isSignUp = false
            }
        } else {
            await sessionStore.signIn(email: email, password: password)
            // Refresh entitlement only if sign-in actually established a session.
            if sessionStore.session != nil {
                await entitlementStore.refresh()
            }
        }
    }
}

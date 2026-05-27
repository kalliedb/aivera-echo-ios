import Foundation
import Supabase

/// Holds the current `AppSession` and exposes auth actions (sign-in, sign-up,
/// sign-out). Restores any persisted session on init via supabase-swift's
/// Keychain-backed storage.
@MainActor
final class SessionStore: ObservableObject {

    @Published private(set) var session: AppSession?
    @Published private(set) var isBusy: Bool = false
    @Published var lastError: String?
    @Published var lastInfo: String?

    private let client = SupabaseConfig.shared

    init() {
        // Restore the persisted session asynchronously — by the time the UI
        // first reads `session` we'll have the right answer.
        Task { await refresh() }
    }

    /// Pulls the current user from the Supabase client (which restores from
    /// Keychain) and publishes a domain `AppSession`. Call after any auth op.
    func refresh() async {
        do {
            let user = try await client.auth.user()
            session = AppSession(userId: user.id.uuidString, email: user.email ?? "")
        } catch {
            session = nil
        }
    }

    // MARK: - Sign in / sign up / sign out

    func signIn(email: String, password: String) async {
        await withBusy {
            try await client.auth.signIn(email: email, password: password)
            await refresh()
        }
    }

    /// Returns true if a session was created immediately (e-mail confirmation
    /// disabled). Returns false if Supabase requires the user to confirm via
    /// the link in their inbox before signing in.
    func signUp(email: String, password: String) async -> Bool {
        var signedInImmediately = false
        await withBusy {
            let response = try await client.auth.signUp(email: email, password: password)
            if response.session != nil {
                await refresh()
                signedInImmediately = true
            } else {
                lastInfo = "Account created. Check your email to confirm, then sign in."
            }
        }
        return signedInImmediately
    }

    func signOut() async {
        await withBusy {
            try await client.auth.signOut()
            session = nil
        }
    }

    // MARK: - Helpers

    private func withBusy(_ work: () async throws -> Void) async {
        isBusy = true
        lastError = nil
        lastInfo = nil
        defer { isBusy = false }
        do {
            try await work()
        } catch {
            lastError = friendly(error)
        }
    }

    private func friendly(_ error: Error) -> String {
        let msg = (error as NSError).localizedDescription
        // Supabase returns "Invalid login credentials" etc. — pass through.
        return msg.isEmpty ? "Something went wrong." : msg
    }
}

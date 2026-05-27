import Foundation

/// Holds the current user's entitlement (Pro / Free) and the tier label.
/// Cached in UserDefaults so the UI doesn't flash "Free" on cold launch
/// before the network probe completes.
@MainActor
final class EntitlementStore: ObservableObject {

    @Published private(set) var entitled: Bool = false
    @Published private(set) var tier: String?

    private let sessionStore: SessionStore
    private let entitledKey = "echo.entitlement.entitled"
    private let tierKey     = "echo.entitlement.tier"

    init(sessionStore: SessionStore) {
        self.sessionStore = sessionStore
        // Restore cached state for snappy launch UI.
        self.entitled = UserDefaults.standard.bool(forKey: entitledKey)
        self.tier     = UserDefaults.standard.string(forKey: tierKey)
    }

    /// Re-check entitlement against the server. Call on sign-in and on app
    /// foreground; clears state if there's no current session.
    func refresh() async {
        guard let session = sessionStore.session else {
            entitled = false
            tier = nil
            UserDefaults.standard.removeObject(forKey: entitledKey)
            UserDefaults.standard.removeObject(forKey: tierKey)
            return
        }
        let result = await EntitlementService.check(email: session.email)
        entitled = result.entitled
        tier = result.tier
        UserDefaults.standard.set(result.entitled, forKey: entitledKey)
        if let t = result.tier {
            UserDefaults.standard.set(t, forKey: tierKey)
        } else {
            UserDefaults.standard.removeObject(forKey: tierKey)
        }
    }

    /// Human-readable label for the AccountSheet "Plan" row.
    var planLabel: String {
        if !entitled { return "Free" }
        switch tier {
        case "lifetime":    return "Lifetime member"
        case "pro_yearly":  return "Pro (annual)"
        case "pro_monthly": return "Pro (monthly)"
        case "comp":        return "Comp"
        default:            return "Pro"
        }
    }
}

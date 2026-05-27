import Foundation

/// Thin HTTP client for the `is-entitled` Edge Function. Returns whether the
/// given email has an active (non-revoked, non-expired) entitlement and what
/// tier it is. Public endpoint — uses the anon key as the apikey header.
enum EntitlementService {

    struct Result {
        let entitled: Bool
        let tier: String?
    }

    static func check(email: String) async -> Result {
        guard SupabaseConfig.isConfigured else { return Result(entitled: false, tier: nil) }

        var components = URLComponents(url: SupabaseConfig.url, resolvingAgainstBaseURL: false)
        components?.path  = "/functions/v1/is-entitled"
        components?.queryItems = [URLQueryItem(name: "email", value: email.lowercased())]
        guard let url = components?.url else { return Result(entitled: false, tier: nil) }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return Result(entitled: false, tier: nil)
            }
            let payload = try JSONDecoder().decode(EntitlementResponse.self, from: data)
            return Result(entitled: payload.entitled, tier: payload.tier)
        } catch {
            print("EntitlementService.check error: \(error)")
            return Result(entitled: false, tier: nil)
        }
    }

    private struct EntitlementResponse: Decodable {
        let entitled: Bool
        let tier: String?
    }
}

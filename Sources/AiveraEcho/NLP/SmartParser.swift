import Foundation

/// FR-AI-001 — Smart parser. Calls the `parse-reminder` Supabase Edge
/// Function (Claude Haiku under the hood) to extract one or more
/// reminders from a natural-language transcript.
///
/// Mirrors `solutions.aivera.echo.nlp.SmartParser` on Android so the two
/// platforms produce identical results for identical inputs.
///
/// Resilience: every failure path (timeout, 4xx, 5xx, malformed JSON,
/// network down) returns an empty array. Callers fall back to their
/// existing local behaviour. The user never sees an "AI failed" toast.
enum SmartParser {

    struct ParsedReminder: Equatable {
        let text: String
        let triggerAt: Date
        let recurrence: Recurrence
    }

    private static let networkTimeout: TimeInterval = 5.0

    /// Returns an empty array when:
    ///   - the input is blank
    ///   - Supabase isn't configured for this build
    ///   - the network call times out or fails
    ///   - the model couldn't extract any reminders
    /// On empty, the caller's local fallback path runs as before.
    static func parse(_ text: String) async -> [ParsedReminder] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard SupabaseConfig.isConfigured else { return [] }

        let url = SupabaseConfig.url.appendingPathComponent("functions/v1/parse-reminder")
        let key = SupabaseConfig.anonKey

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = networkTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        let body = ParseRequest(text: trimmed, nowIso: isoNow())
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            return []
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return []
            }
            let decoded = try JSONDecoder().decode(ParseResponse.self, from: data)
            return decoded.reminders.compactMap { dto -> ParsedReminder? in
                let safeText = dto.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !safeText.isEmpty, dto.triggerAt > 0 else { return nil }
                let triggerAt = Date(timeIntervalSince1970: TimeInterval(dto.triggerAt) / 1000)
                let recurrence = Recurrence(rawValue: dto.recurrence.uppercased()) ?? .none
                return ParsedReminder(text: safeText, triggerAt: triggerAt, recurrence: recurrence)
            }
        } catch {
            // Timeout, cancellation, network unreachable, decode error —
            // all silent. Local fallback handles the user-facing behaviour.
            return []
        }
    }

    /// ISO-8601 with the device's local offset, so the edge function's
    /// LLM call sees the same wall clock the user is looking at.
    private static func isoNow() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date())
    }

    // MARK: - DTOs

    private struct ParseRequest: Encodable {
        let text: String
        let nowIso: String
    }

    private struct ParseResponse: Decodable {
        let reminders: [ParsedReminderDto]
    }

    private struct ParsedReminderDto: Decodable {
        let text: String
        let triggerAt: Int64
        let recurrence: String
    }
}

import Foundation
import Supabase

/// FR-INT-001 — Thin client for the three WhatsApp Edge Functions:
///   /functions/v1/whatsapp-verify  → starts OTP handshake
///   /functions/v1/whatsapp-confirm → completes it
///   /functions/v1/whatsapp-send    → dispatches a reminder
///
/// All three require the user JWT. We grab the current token from
/// `supabase-swift`'s session storage on every call so refresh works
/// transparently — see [token] below.
///
/// Network policy mirrors Android (`solutions.aivera.echo.sync.WhatsAppClient`):
/// 12s timeout for verify (Meta sometimes blocks 6-8s on cold templates),
/// 10s elsewhere; any failure surfaces as a sealed result so the UI can show
/// a friendly message without parsing HTTPURLResponse codes itself.
enum WhatsAppClient {

    // MARK: - Result types

    enum VerifyResult: Equatable {
        case sent(maskedPhone: String, expiresInSeconds: Int)
        case failed(message: String)
        case notSignedIn
    }

    enum ConfirmResult: Equatable {
        case verified(maskedPhone: String)
        case failed(message: String)
        case codeExpired
        case notSignedIn
    }

    // MARK: - Public API

    /// Start the OTP handshake. Caller surfaces the result via the
    /// `WhatsAppUi` state machine on the view side.
    static func verify(phoneE164: String) async -> VerifyResult {
        guard let token = await token() else { return .notSignedIn }
        let payload = VerifyRequest(phone: phoneE164)
        do {
            let response: VerifyResponse = try await post(
                path: "whatsapp-verify",
                payload: payload,
                token: token,
                timeout: 12
            )
            return .sent(
                maskedPhone: response.maskedPhone ?? phoneE164,
                expiresInSeconds: response.expiresInSeconds ?? 600
            )
        } catch let HTTPError.status(code, body) {
            switch code {
            case 429:
                return .failed(message: extractError(body) ?? "Slow down — try again in a minute")
            default:
                return .failed(message: extractError(body) ?? "Couldn't send the code")
            }
        } catch {
            return .failed(message: error.localizedDescription)
        }
    }

    /// Submit the 6-digit code the user typed.
    static func confirm(code: String) async -> ConfirmResult {
        guard let token = await token() else { return .notSignedIn }
        let payload = ConfirmRequest(code: code)
        do {
            let response: ConfirmResponse = try await post(
                path: "whatsapp-confirm",
                payload: payload,
                token: token,
                timeout: 10
            )
            return .verified(maskedPhone: response.maskedPhone ?? "•••• ••••")
        } catch let HTTPError.status(code, body) {
            switch code {
            case 400:
                return .failed(message: extractError(body) ?? "Code didn't match")
            case 410:
                return .codeExpired
            default:
                return .failed(message: extractError(body) ?? "Couldn't verify")
            }
        } catch {
            return .failed(message: error.localizedDescription)
        }
    }

    /// Fire-and-forget WhatsApp dispatch when a reminder triggers.
    /// Returns true iff the server reported a delivered message; every other
    /// outcome (no subscription, opted-out, network down) yields false and is
    /// swallowed by the caller — the local notification stays source of truth.
    @discardableResult
    static func send(text: String) async -> Bool {
        guard let token = await token() else { return false }
        let payload = SendRequest(text: text)
        do {
            let response: SendResponse = try await post(
                path: "whatsapp-send",
                payload: payload,
                token: token,
                timeout: 10
            )
            return response.delivered == true
        } catch {
            return false
        }
    }

    // MARK: - Internals

    /// Read the current JWT from supabase-swift. Returns nil when signed out
    /// or when the persisted session has expired and can't be refreshed.
    private static func token() async -> String? {
        do {
            let session = try await SupabaseConfig.shared.auth.session
            return session.accessToken
        } catch {
            return nil
        }
    }

    private enum HTTPError: Error {
        case status(code: Int, body: String)
    }

    private static func post<Req: Encodable, Resp: Decodable>(
        path: String,
        payload: Req,
        token: String,
        timeout: TimeInterval
    ) async throws -> Resp {
        let url = SupabaseConfig.url.appendingPathComponent("functions/v1/\(path)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw HTTPError.status(code: 0, body: "")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw HTTPError.status(code: http.statusCode, body: body)
        }
        return try JSONDecoder().decode(Resp.self, from: data)
    }

    /// Pull a server "error" field out of a Supabase function error body.
    /// Uses proper JSON parsing so nested escaped strings (e.g. Meta's
    /// `"Meta 400: {\"error\":...}"`) come through readably instead of being
    /// truncated at the first escaped quote — the regex-with-capture-groups
    /// approach had this bug because [^"]+ stops at any literal " byte,
    /// including the \" in escaped JSON.
    private static func extractError(_ body: String) -> String? {
        guard !body.isEmpty,
              let data = body.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data),
              let dict = parsed as? [String: Any]
        else { return nil }
        for key in ["error", "error_description", "message"] {
            if let value = dict[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    // MARK: - DTOs

    private struct VerifyRequest: Encodable { let phone: String }
    private struct ConfirmRequest: Encodable { let code: String }
    private struct SendRequest: Encodable { let text: String }

    private struct VerifyResponse: Decodable {
        let expiresInSeconds: Int?
        let maskedPhone: String?
        let error: String?
    }

    private struct ConfirmResponse: Decodable {
        let verified: Bool?
        let maskedPhone: String?
        let error: String?
    }

    private struct SendResponse: Decodable {
        let delivered: Bool?
        let messageId: String?
        let reason: String?
        let error: String?
    }
}

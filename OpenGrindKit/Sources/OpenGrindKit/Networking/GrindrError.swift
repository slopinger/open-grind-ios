import Foundation

/// What a ban applies to.
public enum BanScope: Sendable, Hashable {
    case profile
    case device
    case network
    case underage
    case unknown
}

/// Why talking to Grindr failed. The app turns these into user-facing text.
public enum GrindrError: Error, Sendable, Hashable {
    /// No connection, DNS or TLS failure.
    case offline
    case timedOut
    /// There is no session; sign in.
    case notSignedIn
    /// Wrong email or password, or the session was revoked.
    case unauthorized
    case banned(BanScope, reason: String?)
    case rateLimited
    /// Cloudflare or another edge answered instead of Grindr. Often temporary.
    case blocked
    /// The API refused the request. `code` is the `urn:gr:err:` type, the
    /// numeric code from the body, or a bare text code such as `CAS-4001`, when
    /// there is one.
    case server(status: Int, code: String?, message: String?)
    /// The profile or conversation is gone, hidden or blocked.
    case unavailable
    /// The feature needs a Grindr subscription.
    case requiresSubscription
    /// The profile text was rejected by moderation.
    case rejectedText
    /// The response did not have the expected shape.
    case invalidResponse(String)
    /// A request was malformed; a bug.
    case invalidRequest(String)
    case mediaTooLarge
    /// Signed out while the request was in flight.
    case cancelled
    case `internal`(String)

    /// Retrying the same request could succeed.
    public var isTransient: Bool {
        switch self {
        case .offline, .timedOut, .rateLimited, .blocked: true
        case .server(let status, _, _): status >= 500 || status == 408
        default: false
        }
    }

    /// The error for a non-success response.
    static func from(_ response: APIResponse) -> GrindrError {
        struct Body: Decodable {
            var type: String?
            /// A number, or text such as `CAS-4001`.
            var code: String?
            var message: String?

            enum CodingKeys: String, CodingKey { case type, code, message }

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                type = container.lenient(String.self, forKey: .type)
                code =
                    container.lenient(String.self, forKey: .code)
                    ?? container.lenient(Int.self, forKey: .code).map(String.init)
                message = container.lenient(String.self, forKey: .message)
            }
        }
        let body = try? JSON.decode(Body.self, from: response.body)
        let urn = body?.type.flatMap { $0.hasPrefix("urn:gr:err:") ? $0 : nil }
        // Some endpoints, such as the cascade, answer with just a code as text.
        let text =
            body == nil
            ? String(data: response.body.prefix(64), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) : nil
        let code = urn ?? body?.code ?? text.flatMap { $0.wholeMatch(of: /[A-Z]+-\d+/) != nil ? $0 : nil }
        switch (response.status, code) {
        case (401, _): return .unauthorized
        case (429, _): return .rateLimited
        // Exploring another place is only for paid subscriptions (seen as a bare "CAS-4001").
        case (_, "urn:gr:err:tiered_feature"), (_, "CAS-4001"): return .requiresSubscription
        case (_, "urn:gr:err:hit_banned_terms"): return .rejectedText
        case (403, "urn:gr:err:unauthorized_action"), (404, _): return .unavailable
        default:
            return .server(status: response.status, code: code, message: body?.message)
        }
    }
}

import Foundation
import OpenGrindCore
import OpenGrindKit

/// The real transport: Open Grind's Rust `grindr` crate, which talks to Grindr
/// with the official Android app's TLS and HTTP/2 fingerprint and headers.
public final class CoreTransport: GrindrTransport, @unchecked Sendable {
    /// The Grindr Android app version requests present as.
    public static var grindrVersion: String { grindrAppVersion() }

    /// A new random device identity to persist and pass to ``init(deviceJSON:credentials:)``.
    public static func makeDevice() -> String { generateDeviceJson() }

    private let client: CoreClient
    private let listener = Listener()
    /// Called after sign-out with the new device identity, so it can be persisted.
    public var onDeviceRotated: (@Sendable (String) -> Void)?

    /// - Parameters:
    ///   - deviceJSON: The persisted device identity, from ``makeDevice()``.
    ///   - credentials: Stored credentials to resume the account with.
    public init(deviceJSON: String, credentials: String?) throws {
        client = try Self.mapErrors {
            try CoreClient(deviceJson: deviceJSON, credentialsJson: credentials)
        }
        client.setListener(listener: listener)
    }

    public func setEventHandler(_ handler: @escaping @Sendable (TransportEvent) -> Void) {
        listener.setHandler(handler)
    }

    public func signIn(email: String, password: String, geohash: String?) async throws -> SignInResult {
        let outcome = try await Self.mapAsyncErrors {
            try await client.signInWithEmail(email: email, password: password, geohash: geohash)
        }
        guard let profileID = Int(outcome.profileId) else {
            throw GrindrError.invalidResponse("profile id \(outcome.profileId)")
        }
        return SignInResult(
            profileID: profileID, restriction: outcome.restriction.map(Self.restriction))
    }

    public func signOut() async throws {
        let device = Self.makeDevice()
        try await Self.mapAsyncErrors { try await client.signOut(newDeviceJson: device) }
        onDeviceRotated?(device)
    }

    public func send(_ request: APIRequest) async throws -> APIResponse {
        let body: RequestBody =
            switch request.body {
            case .empty: .empty
            case .json(let data): .json(json: String(decoding: data, as: UTF8.self))
            case .bytes(let contentType, let data): .bytes(contentType: contentType, bytes: data)
            }
        let response = try await Self.mapAsyncErrors {
            try await client.request(
                method: request.method.rawValue, path: request.path, body: body,
                authenticated: request.isAuthenticated)
        }
        return APIResponse(status: Int(response.status), body: response.body)
    }

    public func fetchMedia(at url: URL, maxBytes: Int) async throws -> MediaPayload {
        let media = try await Self.mapAsyncErrors {
            try await client.fetchMedia(url: url.absoluteString, maxBytes: UInt64(maxBytes))
        }
        return MediaPayload(status: Int(media.status), contentType: media.contentType, data: media.body)
    }

    public func connectRealtime() async throws {
        try await Self.mapAsyncErrors { try await client.connect() }
    }

    public func sendRealtimeCommand(type: String, refID: String, payload: Data) async throws {
        try await Self.mapAsyncErrors {
            try await client.sendWebsocketCommand(
                commandType: type, refId: refID, payloadJson: String(decoding: payload, as: UTF8.self))
        }
    }

    public func setActive(_ isActive: Bool) {
        client.setActive(active: isActive)
    }

    // MARK: Mapping

    private static func restriction(
        _ restriction: OpenGrindCore.AccountRestriction
    ) -> OpenGrindKit.AccountRestriction {
        switch restriction {
        case .ageVerification(let region): .ageVerification(region: region)
        case .timedBan(let expiresAt, let reason):
            .temporaryBan(
                until: expiresAt.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) },
                reason: reason)
        case .trustVendorRejected: .rejectedByTrustVendor
        case .other(let value): .other(value)
        }
    }

    static func error(_ error: CoreError) -> GrindrError {
        switch error {
        case .Network: .offline
        case .Timeout: .timedOut
        case .Auth: .notSignedIn
        case .Api(let code, let message): .server(status: Int(code), code: nil, message: message)
        case .Unauthorized: .unauthorized
        case .Banned(let scope, _, _, let reason): .banned(Self.scope(scope), reason: reason)
        case .RateLimited: .rateLimited
        case .Blocked: .blocked
        case .InvalidRequest(let message): .invalidRequest(message)
        case .SessionCleared: .cancelled
        case .MediaTooLarge: .mediaTooLarge
        case .Internal(let message): .internal(message)
        }
    }

    private static func scope(_ scope: OpenGrindCore.BanScope) -> OpenGrindKit.BanScope {
        switch scope {
        case .profile: .profile
        case .device: .device
        case .network: .network
        case .underage: .underage
        case .unknown: .unknown
        }
    }

    private static func mapErrors<T>(_ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch let error as CoreError {
            throw Self.error(error)
        }
    }

    private static func mapAsyncErrors<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let error as CoreError {
            throw Self.error(error)
        }
    }
}

/// Receives the Rust client's callbacks (on its own threads) and forwards them.
private final class Listener: CoreListener, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (TransportEvent) -> Void)?
    /// Events from before a handler was set, e.g. the resumed credentials.
    private var backlog: [TransportEvent] = []

    func setHandler(_ handler: @escaping @Sendable (TransportEvent) -> Void) {
        let backlog = lock.withLock {
            self.handler = handler
            defer { self.backlog = [] }
            return self.backlog
        }
        backlog.forEach(handler)
    }

    private func emit(_ event: TransportEvent) {
        let handler = lock.withLock {
            if self.handler == nil { backlog.append(event) }
            return self.handler
        }
        handler?(event)
    }

    func credentialsChanged(credentialsJson: String?) {
        emit(.credentialsChanged(credentialsJson))
    }

    func websocketEvent(eventType: String, eventJson: String) {
        emit(.realtime(type: eventType, json: Data(eventJson.utf8)))
    }

    func websocketStateChanged(connected: Bool) {
        emit(.realtimeConnectionChanged(isConnected: connected))
    }

    func authNotice(notice: AuthNotice) {
        switch notice {
        case .signedOut: emit(.sessionEnded(banned: false, reason: nil))
        case .banned(_, let reason): emit(.sessionEnded(banned: true, reason: reason))
        case .refreshFailed(_, let transient): emit(.refreshFailed(isTransient: transient))
        case .refreshRecovered: emit(.refreshRecovered)
        }
    }
}

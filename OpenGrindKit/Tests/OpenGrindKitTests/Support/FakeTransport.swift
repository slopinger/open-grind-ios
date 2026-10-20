import Foundation

@testable import OpenGrindKit

/// A transport that answers from a closure and records every request.
final class FakeTransport: GrindrTransport, @unchecked Sendable {
    typealias Handler = @Sendable (APIRequest) throws -> APIResponse

    private let lock = NSLock()
    private var handler: Handler
    private var eventHandler: (@Sendable (TransportEvent) -> Void)?
    private var recorded: [APIRequest] = []
    var signInResult = SignInResult(profileID: 1)

    init(_ handler: @escaping Handler = { _ in APIResponse(status: 200, body: Data("{}".utf8)) }) {
        self.handler = handler
    }

    var requests: [APIRequest] { lock.withLock { recorded } }

    func respond(_ handler: @escaping Handler) {
        lock.withLock { self.handler = handler }
    }

    func emit(_ event: TransportEvent) {
        lock.withLock { eventHandler }?(event)
    }

    func setEventHandler(_ handler: @escaping @Sendable (TransportEvent) -> Void) {
        lock.withLock { eventHandler = handler }
    }

    func signIn(email: String, password: String, geohash: String?) async throws -> SignInResult {
        emit(.credentialsChanged(#"{"profile_id":"\#(signInResult.profileID)","auth_token":"t"}"#))
        return signInResult
    }

    func signOut() async throws {
        emit(.credentialsChanged(nil))
    }

    func send(_ request: APIRequest) async throws -> APIResponse {
        let handler = lock.withLock {
            recorded.append(request)
            return self.handler
        }
        return try handler(request)
    }

    func fetchMedia(at url: URL, maxBytes: Int) async throws -> MediaPayload {
        MediaPayload(status: 404, data: Data())
    }

    func connectRealtime() async throws {}

    func setActive(_ isActive: Bool) {}
}

extension APIResponse {
    static func json(_ string: String, status: Int = 200) -> APIResponse {
        APIResponse(status: status, body: Data(string.utf8))
    }
}

extension APIRequest {
    /// The JSON body as a dictionary, for assertions.
    var jsonObject: [String: Any]? {
        guard case .json(let data) = body else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

/// Waits until `condition` holds, for state that changes in a spawned task.
@MainActor
func eventually(timeout: Duration = .seconds(3), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        if ContinuousClock.now > deadline { return false }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return true
}

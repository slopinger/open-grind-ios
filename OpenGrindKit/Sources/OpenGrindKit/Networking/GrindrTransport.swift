import Foundation

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

/// A request to the Grindr REST API.
public struct APIRequest: Sendable, Hashable {
    public enum Body: Sendable, Hashable {
        case empty
        case json(Data)
        case bytes(contentType: String, Data)
    }

    public var method: HTTPMethod
    /// Path and query, starting with `/`.
    public var path: String
    public var body: Body
    public var isAuthenticated: Bool

    public init(
        _ method: HTTPMethod, _ path: String, body: Body = .empty, isAuthenticated: Bool = true
    ) {
        self.method = method
        self.path = path
        self.body = body
        self.isAuthenticated = isAuthenticated
    }

    /// `path` is already percent-encoded: IDs in it are escaped where it is built.
    init(_ method: HTTPMethod, _ path: String, query: [URLQueryItem], body: Body = .empty) {
        var components = URLComponents()
        components.percentEncodedPath = path
        components.queryItems = query.isEmpty ? nil : query
        self.init(method, components.string ?? path, body: body)
    }

    static func json(_ method: HTTPMethod, _ path: String, _ body: JSONValue) throws -> APIRequest {
        APIRequest(method, path, body: .json(try JSON.encode(body)))
    }
}

/// A REST response, whatever its status.
public struct APIResponse: Sendable, Hashable {
    public var status: Int
    public var body: Data

    public init(status: Int, body: Data = Data()) {
        self.status = status
        self.body = body
    }

    public var isSuccess: Bool { (200..<300).contains(status) }
}

/// A file from the CDN.
public struct MediaPayload: Sendable, Hashable {
    public var status: Int
    public var contentType: String?
    public var data: Data

    public init(status: Int, contentType: String? = nil, data: Data) {
        self.status = status
        self.contentType = contentType
        self.data = data
    }
}

/// An account restriction that comes with an otherwise valid session.
public enum AccountRestriction: Sendable, Hashable {
    case ageVerification(region: String)
    case temporaryBan(until: Date?, reason: String?)
    case rejectedByTrustVendor
    case other(String)
}

public struct SignInResult: Sendable, Hashable {
    public var profileID: ProfileID
    public var restriction: AccountRestriction?

    public init(profileID: ProfileID, restriction: AccountRestriction? = nil) {
        self.profileID = profileID
        self.restriction = restriction
    }
}

/// Something the transport noticed in the background.
public enum TransportEvent: Sendable, Hashable {
    /// The durable credentials changed. Persist them securely; `nil` means
    /// signed out, so delete what was stored.
    case credentialsChanged(String?)
    /// A realtime event: its `type` and the whole event as JSON.
    case realtime(type: String, json: Data)
    case realtimeConnectionChanged(isConnected: Bool)
    /// The server ended the session.
    case sessionEnded(banned: Bool, reason: String?)
}

/// The connection to Grindr: authentication, REST, CDN and realtime.
///
/// The app uses `CoreTransport` (the Rust `grindr` transport with the official
/// app's network fingerprint) or `DemoTransport` (local sample data). Tests use
/// their own.
public protocol GrindrTransport: AnyObject, Sendable {
    /// Receives background events. Called on arbitrary threads.
    func setEventHandler(_ handler: @escaping @Sendable (TransportEvent) -> Void)

    func signIn(email: String, password: String, geohash: String?) async throws -> SignInResult

    /// Ends the session and gives the device a new identity, so the next
    /// sign-in cannot be linked to this one.
    func signOut() async throws

    func send(_ request: APIRequest) async throws -> APIResponse

    /// Downloads a CDN file, failing with ``GrindrError/mediaTooLarge`` past `maxBytes`.
    func fetchMedia(at url: URL, maxBytes: Int) async throws -> MediaPayload

    /// Opts in to realtime events; the transport reconnects on its own.
    func connectRealtime() async throws

    /// Follows the app into the foreground (`true`) and background.
    func setActive(_ isActive: Bool)
}

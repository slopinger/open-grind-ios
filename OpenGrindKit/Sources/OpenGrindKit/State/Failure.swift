import Foundation

/// Why the device location is not available.
public enum LocationError: Error, Sendable, Hashable {
    /// The user declined location access.
    case denied
    /// Location access is restricted, for example by Screen Time.
    case restricted
    /// The device could not determine its location.
    case unavailable
}

/// Something a screen failed to do, in terms the app can explain.
public enum Failure: Error, Sendable, Hashable {
    case grindr(GrindrError)
    case location(LocationError)
    case unexpected(String)

    public init(_ error: any Error) {
        switch error {
        case let failure as Failure: self = failure
        case let error as GrindrError: self = .grindr(error)
        case let error as LocationError: self = .location(error)
        default: self = .unexpected(String(describing: error))
        }
    }
}

/// The loading state of a screen's content.
public enum LoadState: Sendable, Hashable {
    case idle
    case loading
    case loaded
    case failed(Failure)

    /// Never loaded, or the last load failed.
    public var needsLoad: Bool { self == .idle || failure != nil }

    public var failure: Failure? {
        if case .failed(let failure) = self { return failure }
        return nil
    }
}

/// Where you are, as a geohash.
public protocol LocationProviding: Sendable {
    /// The current location. Throws ``LocationError``.
    func currentGeohash() async throws -> String
}

/// A fixed location, for the demo and tests.
public struct FixedLocation: LocationProviding {
    public var geohash: String

    public init(geohash: String) {
        self.geohash = geohash
    }

    public func currentGeohash() async throws -> String { geohash }
}

/// Persists the account's credentials. The app stores them in the Keychain.
public protocol CredentialStore: Sendable {
    func loadCredentials() -> String?
    func saveCredentials(_ credentials: String?)
}

/// Keeps credentials in memory, for the demo and tests.
public final class InMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var credentials: String?

    public init(credentials: String? = nil) {
        self.credentials = credentials
    }

    public func loadCredentials() -> String? {
        lock.withLock { credentials }
    }

    public func saveCredentials(_ credentials: String?) {
        lock.withLock { self.credentials = credentials }
    }
}

/// The profile id inside the transport's credentials JSON, if any.
public func profileID(fromCredentials credentials: String) -> ProfileID? {
    struct Credentials: Decodable {
        var profileID: ProfileID?

        enum CodingKeys: String, CodingKey { case profileId = "profile_id" }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            profileID = container.flexibleInt(forKey: .profileId)
        }
    }
    return (try? JSON.decode(Credentials.self, from: Data(credentials.utf8)))?.profileID
}

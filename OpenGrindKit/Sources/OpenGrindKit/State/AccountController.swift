import Foundation
import Observation

/// Why the app is back at the sign-in screen without the user signing out.
public enum SignedOutReason: Sendable, Hashable {
    /// The server ended the session, e.g. the password changed.
    case sessionExpired
    case banned(reason: String?)
}

/// Signs in and out, and owns the signed-in ``AccountSession``.
@MainActor
@Observable
public final class AccountController {
    public enum State {
        case signedOut
        case signedIn(AccountSession)
    }

    public private(set) var state: State
    /// Set when the server signed the account out; shown on the sign-in screen.
    public var signedOutReason: SignedOutReason?
    /// The sign-in came with a restriction the user should know about.
    public var restriction: AccountRestriction?

    public let isDemo: Bool
    private let transport: any GrindrTransport
    private let credentials: any CredentialStore
    private let location: any LocationProviding
    private let preferences: (any PreferenceStore)?

    /// Creates the controller and resumes the stored account, if any.
    ///
    /// The transport must have been created with `credentials`' stored value.
    public init(
        transport: any GrindrTransport, credentials: any CredentialStore,
        location: any LocationProviding, preferences: (any PreferenceStore)? = nil,
        isDemo: Bool = false
    ) {
        self.transport = transport
        self.credentials = credentials
        self.location = location
        self.preferences = preferences
        self.isDemo = isDemo
        state = .signedOut

        transport.setEventHandler { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        if let stored = credentials.loadCredentials(),
            let profileID = profileID(fromCredentials: stored)
        {
            startSession(profileID: profileID)
        }
    }

    public var session: AccountSession? {
        if case .signedIn(let session) = state { return session }
        return nil
    }

    /// Signs in, tagging the sign-in with your location when it is available.
    public func signIn(email: String, password: String) async throws {
        let geohash = try? await location.currentGeohash()
        let result = try await transport.signIn(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password,
            geohash: geohash.map(Geohash.coarsen))
        signedOutReason = nil
        restriction = result.restriction
        startSession(profileID: result.profileID)
    }

    /// Signs out and forgets the account's session and preferences.
    public func signOut() async {
        if let session { preferences?.saveBrowseFilters(nil, for: session.profileID) }
        session?.stop()
        state = .signedOut
        credentials.saveCredentials(nil)
        try? await transport.signOut()
    }

    /// Follows the app into the foreground and background.
    public func setActive(_ isActive: Bool) {
        transport.setActive(isActive)
        if isActive { session?.becameActive() }
    }

    private func startSession(profileID: ProfileID) {
        let session = AccountSession(
            profileID: profileID, api: GrindrAPI(transport: transport), location: location,
            preferences: preferences)
        state = .signedIn(session)
        session.start()
    }

    private func handle(_ event: TransportEvent) {
        switch event {
        case .credentialsChanged(let stored):
            credentials.saveCredentials(stored)
            if stored == nil, session != nil {
                endSession(.sessionExpired)
            }
        case .sessionEnded(let banned, let reason):
            endSession(banned ? .banned(reason: reason) : .sessionExpired)
        case .realtime(let type, let json):
            session?.receive(RealtimeEvent.decode(type: type, json: json))
        case .realtimeConnectionChanged(let isConnected):
            session?.isRealtimeConnected = isConnected
        case .refreshFailed, .refreshRecovered:
            break
        }
    }

    private func endSession(_ reason: SignedOutReason) {
        guard let session else { return }
        session.stop()
        state = .signedOut
        signedOutReason = reason
    }
}

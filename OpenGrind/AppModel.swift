import Foundation
import Observation
import OpenGrindCoreTransport
import OpenGrindKit

/// The app's top-level state: which transport is in use (Grindr or the demo)
/// and the account on top of it.
@MainActor
@Observable
final class AppModel {
    /// The account and what belongs to its transport, replaced together.
    private struct Setup {
        var account: AccountController
        var images: ImagePipeline
        var location: LocationChoice
        var failure: Failure?
    }

    private var setup: Setup

    var account: AccountController { setup.account }
    var images: ImagePipeline { setup.images }
    /// Your device's location or a place you chose instead, for everything sent to Grindr.
    var locationChoice: LocationChoice { setup.location }
    /// The transport could not be set up; shown instead of the sign-in screen.
    var startupFailure: Failure? { setup.failure }

    let location = LocationService()

    @ObservationIgnored private let keychain = KeychainStore()

    private static let demoKey = "demoMode"

    init() {
        // Also set by the launch argument `-demoMode YES`.
        let isDemo = UserDefaults.standard.bool(forKey: Self.demoKey)
        setup = Self.makeSetup(isDemo: isDemo, keychain: keychain, location: location)
    }

    var isDemo: Bool { account.isDemo }

    /// Switches to sample data, without touching a stored Grindr account.
    func startDemo() {
        UserDefaults.standard.set(true, forKey: Self.demoKey)
        rebuild(isDemo: true)
    }

    /// Leaves the demo and returns to the sign-in screen.
    func endDemo() {
        UserDefaults.standard.set(false, forKey: Self.demoKey)
        rebuild(isDemo: false)
    }

    func signOut() async {
        if isDemo {
            endDemo()
            return
        }
        await account.signOut()
    }

    private func rebuild(isDemo: Bool) {
        setup = Self.makeSetup(isDemo: isDemo, keychain: keychain, location: location)
    }

    private static func makeSetup(isDemo: Bool, keychain: KeychainStore, location: LocationService) -> Setup {
        if isDemo {
            let transport = DemoTransport(loadImage: loadDemoAvatar)
            // A place chosen in the demo is not remembered, and the real one isn't used.
            let choice = LocationChoice(device: FixedLocation(geohash: DemoTransport.geohash))
            let account = AccountController(
                transport: transport,
                credentials: InMemoryCredentialStore(credentials: DemoTransport.credentials),
                location: choice.location, preferences: DefaultsPreferenceStore(), isDemo: true)
            return Setup(account: account, images: ImagePipeline(transport: transport), location: choice)
        }

        let device: String
        if let stored = keychain.device {
            device = stored
        } else {
            device = CoreTransport.makeDevice()
            keychain.device = device
        }
        let transport: CoreTransport
        do {
            transport = try CoreTransport(deviceJSON: device, credentials: keychain.loadCredentials())
        } catch {
            // Stored data this version cannot read. Sign out, but keep the device unless it is
            // the problem: a new device looks riskier to Grindr's bot protection.
            keychain.saveCredentials(nil)
            if let signedOut = try? CoreTransport(deviceJSON: device, credentials: nil) {
                transport = signedOut
            } else {
                let fresh = CoreTransport.makeDevice()
                keychain.device = fresh
                do {
                    transport = try CoreTransport(deviceJSON: fresh, credentials: nil)
                } catch {
                    var demo = makeSetup(isDemo: true, keychain: keychain, location: location)
                    demo.failure = Failure(error)
                    return demo
                }
            }
        }
        transport.onDeviceRotated = { [keychain] device in keychain.device = device }
        let preferences = DefaultsPreferenceStore()
        let choice = LocationChoice(device: location, preferences: preferences)
        let account = AccountController(
            transport: transport, credentials: keychain, location: choice.location, preferences: preferences)
        let images = ImagePipeline(transport: transport)
        account.onSignOut = { await images.removeAll() }
        return Setup(account: account, images: images, location: choice)
    }

    /// A demo avatar from DiceBear, which serves about ten PNGs a second and
    /// answers the rest with 429 (no Retry-After), as a full grid would get.
    @concurrent
    nonisolated private static func loadDemoAvatar(_ url: URL) async throws -> Data {
        for attempt in 1...5 {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 429 else { return data }
            try await Task.sleep(for: .milliseconds(400 * attempt))
        }
        throw URLError(.resourceUnavailable)
    }
}

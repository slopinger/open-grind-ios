import Foundation
import Observation
import OpenGrindCoreTransport
import OpenGrindKit

/// The app's top-level state: which transport is in use (Grindr or the demo)
/// and the account on top of it.
@MainActor
@Observable
final class AppModel {
    private(set) var account: AccountController
    private(set) var images: ImagePipeline
    /// The transport could not be set up; shown instead of the sign-in screen.
    private(set) var startupFailure: Failure?

    let location = LocationService()

    @ObservationIgnored private let keychain = KeychainStore()

    private static let demoKey = "demoMode"

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let isDemo =
            UserDefaults.standard.bool(forKey: Self.demoKey) || arguments.contains("-OpenGrindDemo")
        let setup = Self.makeAccount(isDemo: isDemo, keychain: keychain, location: location)
        account = setup.account
        images = setup.images
        startupFailure = setup.failure
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
        await images.removeAll()
    }

    private func rebuild(isDemo: Bool) {
        let setup = Self.makeAccount(isDemo: isDemo, keychain: keychain, location: location)
        account = setup.account
        images = setup.images
        startupFailure = setup.failure
    }

    private static func makeAccount(
        isDemo: Bool, keychain: KeychainStore, location: LocationService
    ) -> (account: AccountController, images: ImagePipeline, failure: Failure?) {
        if isDemo {
            let transport = DemoTransport(loadImage: { url in
                try await URLSession.shared.data(from: url).0
            })
            let account = AccountController(
                transport: transport,
                credentials: InMemoryCredentialStore(credentials: DemoTransport.credentials),
                location: FixedLocation(geohash: DemoTransport.geohash), isDemo: true)
            return (account, ImagePipeline(transport: transport), nil)
        }

        let device = keychain.device ?? CoreTransport.makeDevice()
        keychain.device = device
        let transport: CoreTransport
        do {
            transport = try CoreTransport(deviceJSON: device, credentials: keychain.loadCredentials())
        } catch {
            // Stored data this version cannot read: start over with a new device.
            keychain.saveCredentials(nil)
            keychain.device = CoreTransport.makeDevice()
            do {
                transport = try CoreTransport(deviceJSON: keychain.device ?? device, credentials: nil)
            } catch {
                let demo = makeAccount(isDemo: true, keychain: keychain, location: location)
                return (demo.account, demo.images, Failure(error))
            }
        }
        transport.onDeviceRotated = { [keychain] device in keychain.device = device }
        let account = AccountController(transport: transport, credentials: keychain, location: location)
        return (account, ImagePipeline(transport: transport), nil)
    }
}

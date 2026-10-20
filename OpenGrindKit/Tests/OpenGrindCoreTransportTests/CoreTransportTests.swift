import Foundation
import OpenGrindKit
import Testing

@testable import OpenGrindCoreTransport

/// Smoke tests of the generated bindings against the real Rust library. They
/// never reach Grindr: every request here is refused before it leaves the device.
struct CoreTransportTests {
    @Test func devicesAreGeneratedAndAccepted() throws {
        let device = CoreTransport.makeDevice()
        let fields = try #require(
            try JSONSerialization.jsonObject(with: Data(device.utf8)) as? [String: Any])
        #expect((fields["device_id"] as? String)?.count == 16)
        #expect(throws: Never.self) { try CoreTransport(deviceJSON: device, credentials: nil) }
        #expect(!CoreTransport.grindrVersion.isEmpty)
    }

    @Test func malformedInputIsAnInvalidRequest() {
        #expect {
            try CoreTransport(deviceJSON: "{}", credentials: nil)
        } throws: { error in
            if case GrindrError.invalidRequest = error { return true }
            return false
        }
    }

    @Test func resumedCredentialsAreReportedToTheHandler() async throws {
        let credentials =
            #"{"email":"a@example.com","profile_id":"42","auth_token":"t","kind":"Email"}"#
        let transport = try CoreTransport(
            deviceJSON: CoreTransport.makeDevice(), credentials: credentials)
        let received = Received()
        transport.setEventHandler { event in
            if case .credentialsChanged(let stored) = event { received.append(stored) }
        }
        let deadline = Date.now.addingTimeInterval(5)
        while received.values.isEmpty, Date.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let stored = try #require(received.values.first ?? nil)
        #expect(profileID(fromCredentials: stored) == 42)
    }

    @Test func pathsMustStayOnTheAPIHost() async throws {
        let transport = try CoreTransport(deviceJSON: CoreTransport.makeDevice(), credentials: nil)
        await #expect {
            try await transport.send(APIRequest(.get, "evil.example/v3/me", isAuthenticated: false))
        } throws: { error in
            if case GrindrError.invalidRequest = error { return true }
            return false
        }
    }
}

private final class Received: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String?] = []

    var values: [String?] { lock.withLock { stored } }

    func append(_ value: String?) {
        lock.withLock { stored.append(value) }
    }
}

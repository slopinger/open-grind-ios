import Foundation
import Observation

/// Where the app tells Grindr you are: your device's location, or a place you
/// chose instead, as Open Grind's location picker does. Signing in, your
/// profile's location and the nearby grid all use it, so with a place chosen
/// the device is never asked where it is.
@MainActor
@Observable
public final class LocationChoice {
    /// The place used instead of your device's location, if you chose one.
    public private(set) var place: ExplorePlace?
    /// What the rest of the app asks for your location.
    public nonisolated let location: any LocationProviding

    @ObservationIgnored private let chosen: ChosenLocation
    @ObservationIgnored private let preferences: (any PreferenceStore)?

    /// - Parameter preferences: Remembers the choice across launches; `nil` keeps it for this run only.
    public init(device: any LocationProviding, preferences: (any PreferenceStore)? = nil) {
        let place = preferences?.chosenPlace()
        chosen = ChosenLocation(device: device, place: place)
        location = chosen
        self.place = place
        self.preferences = preferences
    }

    /// Appears at `place` from now on; `nil` goes back to the device's location.
    /// Call ``AccountSession/locationChanged()`` to move there at once.
    public func choose(_ place: ExplorePlace?) {
        self.place = place
        chosen.place = place
        preferences?.saveChosenPlace(place)
    }
}

/// Answers with the chosen place when there is one, or asks the device.
private final class ChosenLocation: LocationProviding, @unchecked Sendable {
    private let device: any LocationProviding
    private let lock = NSLock()
    private var _place: ExplorePlace?

    init(device: any LocationProviding, place: ExplorePlace?) {
        self.device = device
        _place = place
    }

    var place: ExplorePlace? {
        get { lock.withLock { _place } }
        set { lock.withLock { _place = newValue } }
    }

    func currentGeohash() async throws -> String {
        if let place { return place.geohash }
        return try await device.currentGeohash()
    }
}

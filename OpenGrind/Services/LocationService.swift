import CoreLocation
import Observation
import OpenGrindKit

/// Finds the device's location for the grid and distances.
///
/// It asks for location only while the app is in use, at the 100 m accuracy
/// the app needs (positions are rounded to about 110 m before they are sent),
/// and works with approximate location too.
@MainActor
@Observable
final class LocationService: NSObject, LocationProviding, CLLocationManagerDelegate {
    private(set) var authorization: CLAuthorizationStatus

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var waiters: [CheckedContinuation<CLLocation, any Error>] = []
    @ObservationIgnored private var lastLocation: CLLocation?

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var isDenied: Bool { authorization == .denied || authorization == .restricted }

    nonisolated func currentGeohash() async throws -> String {
        let location = try await currentLocation()
        return Geohash.encode(
            latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }

    /// The current location; a fix from the last two minutes is reused.
    func currentLocation() async throws -> CLLocation {
        if let lastLocation, lastLocation.timestamp.timeIntervalSinceNow > -120 {
            return lastLocation
        }
        switch manager.authorizationStatus {
        case .denied: throw LocationError.denied
        case .restricted: throw LocationError.restricted
        default: break
        }
        return try await withCheckedThrowingContinuation { continuation in
            waiters.append(continuation)
            guard waiters.count == 1 else { return }
            if manager.authorizationStatus == .notDetermined {
                manager.requestWhenInUseAuthorization()
            } else {
                manager.requestLocation()
            }
        }
    }

    private func finish(_ result: Result<CLLocation, LocationError>) {
        let waiters = waiters
        self.waiters = []
        for waiter in waiters {
            waiter.resume(with: result.mapError { $0 as any Error })
        }
    }

    // MARK: CLLocationManagerDelegate (called on the main thread)

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            authorization = manager.authorizationStatus
            switch manager.authorizationStatus {
            case .denied: finish(.failure(.denied))
            case .restricted: finish(.failure(.restricted))
            case .authorizedWhenInUse, .authorizedAlways:
                if !waiters.isEmpty { manager.requestLocation() }
            default: break
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]
    ) {
        MainActor.assumeIsolated {
            guard let location = locations.last else { return }
            lastLocation = location
            finish(.success(location))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        MainActor.assumeIsolated {
            let denied = (error as? CLError)?.code == .denied
            finish(.failure(denied ? .denied : .unavailable))
        }
    }
}

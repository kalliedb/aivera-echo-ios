import CoreLocation
import Foundation

/// One-shot location queries + permission handling. Separate from
/// `GeofenceManager` (which has its own CLLocationManager just for region
/// monitoring) so the two delegate roles don't tangle.
@MainActor
final class LocationManager: NSObject, ObservableObject {

    @Published private(set) var authorizationStatus: CLAuthorizationStatus

    private let manager = CLLocationManager()
    private var pendingLocation: CheckedContinuation<CLLocation, Error>?

    override init() {
        self.authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Prompt for "When In Use" if undetermined. Geofencing later upgrades to
    /// "Always" automatically when the first region is registered.
    func requestWhenInUseIfNeeded() {
        guard authorizationStatus == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    /// One-shot current location. Throws if permission is denied or fails.
    func currentLocation() async throws -> CLLocation {
        // Request permission if we don't have it yet.
        if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
            try? await Task.sleep(nanoseconds: 600_000_000) // give iOS time to surface the prompt
        }
        guard authorizationStatus == .authorizedWhenInUse
            || authorizationStatus == .authorizedAlways else {
            throw LocationError.permissionDenied
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.pendingLocation = continuation
            manager.requestLocation()
        }
    }

    enum LocationError: LocalizedError {
        case permissionDenied
        var errorDescription: String? {
            "Location access is needed to set place reminders. Enable it in Settings → Privacy → Location Services → Aivera Echo."
        }
    }
}

extension LocationManager: CLLocationManagerDelegate {

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.authorizationStatus = status }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.first else { return }
        Task { @MainActor in
            pendingLocation?.resume(returning: loc)
            pendingLocation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            pendingLocation?.resume(throwing: error)
            pendingLocation = nil
        }
    }
}

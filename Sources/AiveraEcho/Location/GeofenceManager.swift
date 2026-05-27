import CoreLocation
import Foundation

/// Registers `CLCircularRegion` monitors keyed on `reminder.id`. When the
/// device enters a region, the delegate fires an immediate local notification
/// via the injected callback. Mirrors Android's GeofenceManager.
@MainActor
final class GeofenceManager: NSObject, ObservableObject {

    /// Set by AppDelegate at startup so this class doesn't need a back-ref.
    var onEnterRegion: ((String) -> Void)?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.allowsBackgroundLocationUpdates = false  // region monitoring doesn't need it
    }

    /// Register the geofence for a location-typed reminder. No-op for time
    /// reminders or for reminders missing lat/lng. Stops any prior monitor on
    /// the same id first so updates are idempotent.
    func register(_ reminder: Reminder) {
        guard reminder.triggerType == .location,
              !reminder.completed,
              let lat = reminder.latitude,
              let lng = reminder.longitude else { return }

        // Geofencing wants Always for background fires. Request the upgrade
        // here; iOS handles the "use only while using app vs always" prompt UX.
        if manager.authorizationStatus == .authorizedWhenInUse {
            manager.requestAlwaysAuthorization()
        } else if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }

        unregister(reminderId: reminder.id)

        let desired = reminder.radiusMeters.map { CLLocationDistance($0) } ?? 200
        let radius  = min(desired, manager.maximumRegionMonitoringDistance)
        let region  = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
            radius: radius,
            identifier: reminder.id
        )
        region.notifyOnEntry = true
        region.notifyOnExit  = false   // ENTER covers the common "remind me here" case
        manager.startMonitoring(for: region)
    }

    func unregister(reminderId: String) {
        for region in manager.monitoredRegions where region.identifier == reminderId {
            manager.stopMonitoring(for: region)
        }
    }

    func unregisterAll() {
        for region in manager.monitoredRegions {
            manager.stopMonitoring(for: region)
        }
    }
}

extension GeofenceManager: CLLocationManagerDelegate {

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        let id = region.identifier
        Task { @MainActor in self.onEnterRegion?(id) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     monitoringDidFailFor region: CLRegion?,
                                     withError error: Error) {
        print("Geofence monitor failed for \(region?.identifier ?? "?"): \(error)")
    }
}

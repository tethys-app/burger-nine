import CoreLocation
import Observation

/// Requests a single foreground location only after the customer explicitly
/// asks for it. Store-distance ranking will plug into this service once the
/// storefront API provides each restaurant's coordinates.
@MainActor
@Observable
final class LocationService: NSObject {
    @ObservationIgnored private let manager = CLLocationManager()

    private(set) var authorizationStatus: CLAuthorizationStatus
    private(set) var location: CLLocation?
    private(set) var isRequesting = false
    private(set) var errorMessage: String?

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    func requestPreciseLocation() {
        guard CLLocationManager.locationServicesEnabled() else {
            errorMessage = "La localisation est désactivée sur cet appareil."
            return
        }

        errorMessage = nil
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            isRequesting = true
            manager.requestLocation()
        case .denied, .restricted:
            errorMessage = "Autorise la localisation dans Réglages pour trouver le Burger Nine le plus proche."
        @unknown default:
            errorMessage = "La position précise est momentanément indisponible."
        }
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            authorizationStatus = manager.authorizationStatus
            if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse {
                isRequesting = true
                manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            location = locations.last
            isRequesting = false
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            isRequesting = false
            errorMessage = "Impossible d’obtenir votre position pour le moment."
        }
    }
}

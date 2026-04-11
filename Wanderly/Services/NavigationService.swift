import Foundation
import MapKit

enum NavigationService {

    enum Mode: String {
        case walking, transit, driving

        var appleMapsKey: String {
            switch self {
            case .walking: return MKLaunchOptionsDirectionsModeWalking
            case .transit: return MKLaunchOptionsDirectionsModeTransit
            case .driving: return MKLaunchOptionsDirectionsModeDriving
            }
        }

        var googleMapsKey: String {
            switch self {
            case .walking: return "walking"
            case .transit: return "transit"
            case .driving: return "driving"
            }
        }
    }

    /// Opens navigation to a place. Prefers Google Maps if installed, falls back to Apple Maps.
    static func navigate(to coordinate: CLLocationCoordinate2D, name: String, mode: Mode = .driving) {
        if openGoogleMaps(to: coordinate, name: name, mode: mode) { return }
        openAppleMaps(to: coordinate, name: name, mode: mode)
    }

    @discardableResult
    private static func openGoogleMaps(to coordinate: CLLocationCoordinate2D, name: String, mode: Mode) -> Bool {
        guard let url = URL(string: "comgooglemaps://"),
              UIApplication.shared.canOpenURL(url) else {
            return false
        }

        let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        guard let directionsURL = URL(string: "comgooglemaps://?daddr=\(coordinate.latitude),\(coordinate.longitude)(\(encodedName))&directionsmode=\(mode.googleMapsKey)") else { return false }
        UIApplication.shared.open(directionsURL)
        return true
    }

    private static func openAppleMaps(to coordinate: CLLocationCoordinate2D, name: String, mode: Mode) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: mode.appleMapsKey])
    }
}

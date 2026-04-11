import Foundation
import CoreLocation

/// Lightweight trip payload encoded in the App Clip URL.
/// Duplicated in WanderlyClip target — keep in sync with main app's copy.
struct SharedTripData: Codable {
    let name: String
    let city: String
    let stops: [SharedStop]

    struct SharedStop: Codable, Identifiable {
        let id: UUID
        let name: String
        let address: String
        let lat: Double
        let lng: Double
        let time: String?
        let note: String?

        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
    }

    // MARK: - URL Encoding

    /// Decode from a wanderly.app URL with base64-encoded `data` query param.
    static func from(url: URL) -> SharedTripData? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let dataParam = components.queryItems?.first(where: { $0.name == "d" })?.value,
              let jsonData = Data(base64Encoded: dataParam) else {
            return nil
        }
        return try? JSONDecoder().decode(SharedTripData.self, from: jsonData)
    }

    /// Encode to a shareable URL.
    func toURL(baseURL: String = "https://wanderly.app/trip") -> URL? {
        guard let jsonData = try? JSONEncoder().encode(self),
              let base64 = jsonData.base64EncodedString().addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        return URL(string: "\(baseURL)?d=\(base64)")
    }
}

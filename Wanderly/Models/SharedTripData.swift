import Foundation
import CoreLocation

/// Lightweight trip payload encoded in the App Clip URL.
/// Duplicated across targets — keep in sync with WanderlyClip's copy.
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

    static func from(url: URL) -> SharedTripData? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let dataParam = components.queryItems?.first(where: { $0.name == "d" })?.value,
              let jsonData = Data(base64Encoded: dataParam) else {
            return nil
        }
        return try? JSONDecoder().decode(SharedTripData.self, from: jsonData)
    }

    func toURL(baseURL: String = "https://wanderly.app/trip") -> URL? {
        guard let jsonData = try? JSONEncoder().encode(self),
              let base64 = jsonData.base64EncodedString().addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        return URL(string: "\(baseURL)?d=\(base64)")
    }

    // MARK: - Convenience Builders

    /// Build from an AI-generated itinerary response + resolved places.
    static func from(title: String, city: String, days: [ItineraryDay], places: [Place]) -> SharedTripData {
        let placeMap = Dictionary(uniqueKeysWithValues: places.map { ($0.id.uuidString, $0) })
        let stops: [SharedStop] = days.flatMap { day in
            day.stops.map { stop in
                let place = stop.placeId.flatMap { placeMap[$0] }
                return SharedStop(
                    id: UUID(),
                    name: stop.placeName,
                    address: place?.address ?? "",
                    lat: place?.latitude ?? 0,
                    lng: place?.longitude ?? 0,
                    time: stop.time,
                    note: stop.note
                )
            }
        }
        return SharedTripData(name: title, city: city, stops: stops)
    }
}

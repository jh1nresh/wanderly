import Foundation
import CoreLocation

// MARK: - Protocol

protocol GooglePlacesServiceProtocol {
    func searchPlace(query: String, near: CLLocationCoordinate2D?) async throws -> [GooglePlaceMatch]
    func getPlaceDetails(placeId: String) async throws -> GooglePlaceDetails
}

// MARK: - Models

struct GooglePlaceMatch: Identifiable, Codable {
    let id: String // placeId
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
    var rating: Double?
    var priceLevel: Int?
}

struct GooglePlaceDetails: Codable {
    var placeId: String
    var name: String
    var formattedAddress: String
    var latitude: Double
    var longitude: Double
    var rating: Double?
    var priceLevel: Int?
    var openingHours: [String]?
    var phoneNumber: String?
    var websiteUrl: String?
    var photoReferences: [String]?
}

// MARK: - Errors

enum GooglePlacesError: LocalizedError {
    case apiKeyMissing
    case noResults
    case networkError(Error)
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .apiKeyMissing: return "Google Places API key not configured"
        case .noResults: return "No matching places found"
        case .networkError(let error): return "Network error: \(error.localizedDescription)"
        case .apiError(let msg): return "Places API: \(msg)"
        }
    }
}

// MARK: - Implementation

final class GooglePlacesService: GooglePlacesServiceProtocol {
    static let shared = GooglePlacesService()

    private let apiKey: String?

    init(apiKey: String? = nil) {
        let resolved = apiKey
            ?? ProcessInfo.processInfo.environment["GOOGLE_PLACES_API_KEY"]
            ?? Self.keyFromPlist("GOOGLE_PLACES_API_KEY")
        self.apiKey = resolved
    }

    private static func keyFromPlist(_ key: String) -> String? {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String],
              let value = dict[key],
              value != "YOUR_KEY_HERE" else { return nil }
        return value
    }

    // MARK: - Text Search

    func searchPlace(query: String, near: CLLocationCoordinate2D?) async throws -> [GooglePlaceMatch] {
        guard let apiKey, !apiKey.isEmpty else {
            throw GooglePlacesError.apiKeyMissing
        }

        var urlString = "https://maps.googleapis.com/maps/api/place/textsearch/json?query=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)&key=\(apiKey)"

        if let location = near {
            urlString += "&location=\(location.latitude),\(location.longitude)&radius=5000"
        }

        guard let url = URL(string: urlString) else {
            throw GooglePlacesError.noResults
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        guard let results = json?["results"] as? [[String: Any]], !results.isEmpty else {
            if let status = json?["status"] as? String, status != "OK" {
                throw GooglePlacesError.apiError(status)
            }
            throw GooglePlacesError.noResults
        }

        return results.prefix(5).compactMap { result in
            guard let placeId = result["place_id"] as? String,
                  let name = result["name"] as? String,
                  let geometry = result["geometry"] as? [String: Any],
                  let location = geometry["location"] as? [String: Any],
                  let lat = location["lat"] as? Double,
                  let lng = location["lng"] as? Double else { return nil }

            return GooglePlaceMatch(
                id: placeId,
                name: name,
                address: result["formatted_address"] as? String ?? "",
                latitude: lat,
                longitude: lng,
                rating: result["rating"] as? Double,
                priceLevel: result["price_level"] as? Int
            )
        }
    }

    // MARK: - Place Details

    func getPlaceDetails(placeId: String) async throws -> GooglePlaceDetails {
        guard let apiKey, !apiKey.isEmpty else {
            throw GooglePlacesError.apiKeyMissing
        }

        let fields = "place_id,name,formatted_address,geometry,rating,price_level,opening_hours,formatted_phone_number,website,photos"
        let urlString = "https://maps.googleapis.com/maps/api/place/details/json?place_id=\(placeId)&fields=\(fields)&key=\(apiKey)"

        guard let url = URL(string: urlString) else {
            throw GooglePlacesError.noResults
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        guard let result = json?["result"] as? [String: Any] else {
            if let status = json?["status"] as? String, status != "OK" {
                throw GooglePlacesError.apiError(status)
            }
            throw GooglePlacesError.noResults
        }

        let geometry = result["geometry"] as? [String: Any]
        let location = geometry?["location"] as? [String: Any]
        let openingHours = result["opening_hours"] as? [String: Any]
        let photos = result["photos"] as? [[String: Any]]

        return GooglePlaceDetails(
            placeId: placeId,
            name: result["name"] as? String ?? "",
            formattedAddress: result["formatted_address"] as? String ?? "",
            latitude: location?["lat"] as? Double ?? 0,
            longitude: location?["lng"] as? Double ?? 0,
            rating: result["rating"] as? Double,
            priceLevel: result["price_level"] as? Int,
            openingHours: openingHours?["weekday_text"] as? [String],
            phoneNumber: result["formatted_phone_number"] as? String,
            websiteUrl: result["website"] as? String,
            photoReferences: photos?.compactMap { $0["photo_reference"] as? String }
        )
    }

    // MARK: - Photo URL

    func photoURL(reference: String, maxWidth: Int = 400) -> URL? {
        guard let apiKey else { return nil }
        return URL(string: "https://maps.googleapis.com/maps/api/place/photo?maxwidth=\(maxWidth)&photo_reference=\(reference)&key=\(apiKey)")
    }
}

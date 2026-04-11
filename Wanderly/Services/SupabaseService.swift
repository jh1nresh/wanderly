import Foundation

// MARK: - Protocol

protocol SupabaseServiceProtocol {
    func fetchPlaces(for userId: String) async throws -> [Place]
    func savePlace(_ place: Place, userId: String) async throws
    func updatePlace(_ place: Place) async throws
    func deletePlace(_ placeId: UUID) async throws
    func fetchTrips(for userId: String) async throws -> [Trip]
    func saveTrip(_ trip: Trip, userId: String) async throws
    func updateTrip(_ trip: Trip) async throws
    func deleteTrip(_ tripId: UUID) async throws
    func fetchProfile(for userId: String) async throws -> UserProfile?
    func updateProfile(_ profile: UserProfile) async throws
}

// MARK: - Errors

enum SupabaseError: LocalizedError {
    case notConfigured
    case notAuthenticated
    case recordNotFound
    case networkError(Error)
    case apiError(Int, String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Supabase not configured"
        case .notAuthenticated: return "User not authenticated"
        case .recordNotFound: return "Record not found"
        case .networkError(let error): return "Network error: \(error.localizedDescription)"
        case .apiError(let code, let msg): return "Supabase error \(code): \(msg)"
        }
    }
}

// MARK: - Implementation

final class SupabaseService: SupabaseServiceProtocol {
    static let shared = SupabaseService()

    private let baseURL: String?
    private let anonKey: String?

    /// Set by auth service after login
    var accessToken: String?

    init() {
        self.baseURL = ProcessInfo.processInfo.environment["SUPABASE_URL"]
            ?? Self.keyFromPlist("SUPABASE_URL")
        self.anonKey = ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"]
            ?? Self.keyFromPlist("SUPABASE_ANON_KEY")
    }

    private static func keyFromPlist(_ key: String) -> String? {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String],
              let value = dict[key],
              value != "YOUR_KEY_HERE",
              !value.isEmpty else { return nil }
        return value
    }

    private var isConfigured: Bool {
        baseURL != nil && anonKey != nil
    }

    // MARK: - Places

    func fetchPlaces(for userId: String) async throws -> [Place] {
        guard isConfigured else { return Place.mockList }

        let data = try await request(
            path: "/rest/v1/places",
            query: "select=*&user_id=eq.\(userId)&order=created_at.desc"
        )

        let rows = try JSONDecoder.supabase.decode([PlaceRow].self, from: data)
        return rows.map { $0.toPlace() }
    }

    func savePlace(_ place: Place, userId: String) async throws {
        guard isConfigured else { return }

        let row = PlaceRow.from(place: place, userId: userId)
        let body = try JSONEncoder.supabase.encode(row)

        try await request(path: "/rest/v1/places", method: "POST", body: body)
    }

    func updatePlace(_ place: Place) async throws {
        guard isConfigured else { return }

        let updates: [String: Any] = [
            "name": place.name,
            "address": place.address,
            "category": place.category.rawValue,
            "status": place.status.rawValue,
            "rating": place.rating as Any,
            "note": place.note as Any,
        ]
        let body = try JSONSerialization.data(withJSONObject: updates)

        try await request(
            path: "/rest/v1/places",
            query: "id=eq.\(place.id)",
            method: "PATCH",
            body: body
        )
    }

    func deletePlace(_ placeId: UUID) async throws {
        guard isConfigured else { return }
        try await request(
            path: "/rest/v1/places",
            query: "id=eq.\(placeId)",
            method: "DELETE"
        )
    }

    // MARK: - Trips

    func fetchTrips(for userId: String) async throws -> [Trip] {
        guard isConfigured else { return Trip.mockList }

        let tripsData = try await request(
            path: "/rest/v1/trips",
            query: "select=*,trip_stops(*)&user_id=eq.\(userId)&order=created_at.desc"
        )

        let rows = try JSONDecoder.supabase.decode([TripRow].self, from: tripsData)
        return rows.map { $0.toTrip() }
    }

    func saveTrip(_ trip: Trip, userId: String) async throws {
        guard isConfigured else { return }

        let row = TripRow.from(trip: trip, userId: userId)
        let body = try JSONEncoder.supabase.encode(row)
        try await request(path: "/rest/v1/trips", method: "POST", body: body)

        // Insert stops
        if !trip.places.isEmpty {
            let stopRows = trip.places.map { TripStopRow.from(stop: $0, tripId: trip.id) }
            let stopsBody = try JSONEncoder.supabase.encode(stopRows)
            try await request(path: "/rest/v1/trip_stops", method: "POST", body: stopsBody)
        }
    }

    func updateTrip(_ trip: Trip) async throws {
        guard isConfigured else { return }

        let updates: [String: Any] = [
            "name": trip.name,
            "city": trip.city,
            "is_optimized": trip.isOptimized,
        ]
        let body = try JSONSerialization.data(withJSONObject: updates)
        try await request(
            path: "/rest/v1/trips",
            query: "id=eq.\(trip.id)",
            method: "PATCH",
            body: body
        )
    }

    func deleteTrip(_ tripId: UUID) async throws {
        guard isConfigured else { return }
        try await request(
            path: "/rest/v1/trips",
            query: "id=eq.\(tripId)",
            method: "DELETE"
        )
    }

    // MARK: - Profile

    func fetchProfile(for userId: String) async throws -> UserProfile? {
        guard isConfigured else { return .mock }

        let data = try await request(
            path: "/rest/v1/profiles",
            query: "select=*&id=eq.\(userId)"
        )

        let rows = try JSONDecoder.supabase.decode([ProfileRow].self, from: data)
        guard let row = rows.first else { return nil }

        // Count places
        let placesData = try await request(
            path: "/rest/v1/places",
            query: "select=id,status&user_id=eq.\(userId)"
        )
        let placeRows = try JSONDecoder.supabase.decode([[String: String]].self, from: placesData)
        let savedCount = placeRows.count
        let visitedCount = placeRows.filter { $0["status"] == "visited" }.count

        // Count cities from trips
        let tripsData = try await request(
            path: "/rest/v1/trips",
            query: "select=city&user_id=eq.\(userId)"
        )
        let tripRows = try JSONDecoder.supabase.decode([[String: String]].self, from: tripsData)
        let cities = Set(tripRows.compactMap { $0["city"] }).count

        return row.toProfile(savedCount: savedCount, visitedCount: visitedCount, citiesCount: cities)
    }

    func updateProfile(_ profile: UserProfile) async throws {
        guard isConfigured else { return }

        let updates: [String: Any] = [
            "display_name": profile.displayName,
            "avatar_url": profile.avatarUrl as Any,
        ]
        let body = try JSONSerialization.data(withJSONObject: updates)
        try await request(
            path: "/rest/v1/profiles",
            query: "id=eq.\(profile.id)",
            method: "PATCH",
            body: body
        )
    }

    // MARK: - HTTP

    @discardableResult
    private func request(
        path: String,
        query: String = "",
        method: String = "GET",
        body: Data? = nil
    ) async throws -> Data {
        guard let baseURL, let anonKey else { throw SupabaseError.notConfigured }

        let separator = query.isEmpty ? "" : "?\(query)"
        guard let url = URL(string: "\(baseURL)\(path)\(separator)") else {
            throw SupabaseError.notConfigured
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")

        // Use access token if available, otherwise anon key
        let token = accessToken ?? anonKey
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        if let body { request.httpBody = body }

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw SupabaseError.apiError(http.statusCode, body)
        }

        return data
    }
}

// MARK: - Row DTOs (snake_case ↔ Swift models)

private struct PlaceRow: Codable {
    let id: UUID
    let user_id: String
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
    let google_place_id: String?
    let category: String
    let status: String
    let rating: Double?
    let note: String?
    let source_url: String?
    let source_platform: String
    let source_image_url: String?
    let extracted_dishes: [String]?
    let price_range: String?
    let recommender: String?
    let google_rating: Double?
    let google_price_level: Int?
    let opening_hours: String?
    let created_at: String

    func toPlace() -> Place {
        Place(
            id: id,
            name: name,
            address: address,
            latitude: latitude,
            longitude: longitude,
            googlePlaceId: google_place_id,
            category: PlaceCategory(rawValue: category) ?? .food,
            status: PlaceStatus(rawValue: status) ?? .wantToGo,
            rating: rating,
            note: note,
            sourceUrl: source_url,
            sourcePlatform: SourcePlatform(rawValue: source_platform) ?? .other,
            sourceImageUrl: source_image_url,
            extractedDishes: extracted_dishes,
            priceRange: price_range,
            recommender: recommender,
            googleRating: google_rating,
            googlePriceLevel: google_price_level,
            openingHours: opening_hours,
            createdAt: ISO8601DateFormatter().date(from: created_at) ?? Date()
        )
    }

    static func from(place: Place, userId: String) -> PlaceRow {
        PlaceRow(
            id: place.id,
            user_id: userId,
            name: place.name,
            address: place.address,
            latitude: place.latitude,
            longitude: place.longitude,
            google_place_id: place.googlePlaceId,
            category: place.category.rawValue,
            status: place.status.rawValue,
            rating: place.rating,
            note: place.note,
            source_url: place.sourceUrl,
            source_platform: place.sourcePlatform.rawValue,
            source_image_url: place.sourceImageUrl,
            extracted_dishes: place.extractedDishes,
            price_range: place.priceRange,
            recommender: place.recommender,
            google_rating: place.googleRating,
            google_price_level: place.googlePriceLevel,
            opening_hours: place.openingHours,
            created_at: ISO8601DateFormatter().string(from: place.createdAt)
        )
    }
}

private struct TripRow: Codable {
    let id: UUID
    let user_id: String
    let name: String
    let city: String
    let start_date: String?
    let end_date: String?
    let is_optimized: Bool
    let created_at: String
    let trip_stops: [TripStopRow]?

    func toTrip() -> Trip {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"

        return Trip(
            id: id,
            name: name,
            city: city,
            startDate: start_date.flatMap { df.date(from: $0) },
            endDate: end_date.flatMap { df.date(from: $0) },
            places: (trip_stops ?? []).map { $0.toStop() },
            isOptimized: is_optimized,
            createdAt: ISO8601DateFormatter().date(from: created_at) ?? Date()
        )
    }

    static func from(trip: Trip, userId: String) -> TripRow {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"

        return TripRow(
            id: trip.id,
            user_id: userId,
            name: trip.name,
            city: trip.city,
            start_date: trip.startDate.map { df.string(from: $0) },
            end_date: trip.endDate.map { df.string(from: $0) },
            is_optimized: trip.isOptimized,
            created_at: ISO8601DateFormatter().string(from: trip.createdAt),
            trip_stops: nil
        )
    }
}

private struct TripStopRow: Codable {
    let id: UUID
    let trip_id: UUID
    let place_id: UUID?
    let place_name: String
    let day: Int
    let order_index: Int
    let start_time: String?
    let duration: Int?
    let note: String?

    func toStop() -> TripStop {
        TripStop(
            id: id,
            placeId: place_id ?? UUID(),
            placeName: place_name,
            day: day,
            orderIndex: order_index,
            startTime: start_time,
            duration: duration,
            note: note
        )
    }

    static func from(stop: TripStop, tripId: UUID) -> TripStopRow {
        TripStopRow(
            id: stop.id,
            trip_id: tripId,
            place_id: stop.placeId,
            place_name: stop.placeName,
            day: stop.day,
            order_index: stop.orderIndex,
            start_time: stop.startTime,
            duration: stop.duration,
            note: stop.note
        )
    }
}

private struct ProfileRow: Codable {
    let id: UUID
    let display_name: String
    let email: String?
    let avatar_url: String?
    let is_premium: Bool
    let created_at: String

    func toProfile(savedCount: Int, visitedCount: Int, citiesCount: Int) -> UserProfile {
        UserProfile(
            id: id,
            displayName: display_name,
            email: email,
            avatarUrl: avatar_url,
            savedCount: savedCount,
            visitedCount: visitedCount,
            citiesCount: citiesCount,
            isPremium: is_premium,
            collections: [],
            createdAt: ISO8601DateFormatter().date(from: created_at) ?? Date()
        )
    }
}

// MARK: - JSON Coding

extension JSONDecoder {
    static let supabase: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()
}

extension JSONEncoder {
    static let supabase: JSONEncoder = {
        let e = JSONEncoder()
        return e
    }()
}

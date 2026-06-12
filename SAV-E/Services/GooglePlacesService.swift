import Foundation
import CoreLocation

// MARK: - Protocol

protocol GooglePlacesServiceProtocol {
    func searchPlace(query: String, near: CLLocationCoordinate2D?) async throws -> [GooglePlaceMatch]
    func getPlaceDetails(placeId: String) async throws -> GooglePlaceDetails
    func photoURL(reference: String, maxWidth: Int) -> URL?
}

// MARK: - Models

struct GooglePlaceMatch: Identifiable, Codable {
    let id: String // placeId
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
    var rating: Double?
    var reviewCount: Int? = nil
    var priceLevel: Int?
    var photoReference: String? = nil
    var types: [String] = []
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
    var types: [String] = []
}

enum PlaceMatchProvider: String, Codable, Hashable {
    case googlePlaces = "google_places"
    case amap
    case baidu

    var displayName: String {
        switch self {
        case .googlePlaces: return "Google Places"
        case .amap: return "Amap"
        case .baidu: return "Baidu Maps"
        }
    }

    var refinementFailureMessage: String {
        switch self {
        case .googlePlaces: return "Google Places refine skipped or failed; confirm exact address/coordinates"
        case .amap: return "Amap refine skipped or failed; confirm exact address/coordinates"
        case .baidu: return "Baidu Maps refine skipped or failed; confirm exact address/coordinates"
        }
    }
}

enum PlaceCoordinateSystem: String, Codable, Hashable {
    case wgs84 = "WGS84"
    case gcj02 = "GCJ-02"
    case bd09 = "BD-09"
}

struct PlaceProviderMatch: Identifiable, Codable, Hashable {
    let provider: PlaceMatchProvider
    let id: String
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
    var rating: Double?
    var reviewCount: Int?
    var priceLevel: Int?
    var types: [String]
    var coordinateSystem: PlaceCoordinateSystem

    var coordinateEvidenceLabel: String {
        switch coordinateSystem {
        case .wgs84:
            return "\(provider.displayName) coordinates"
        case .gcj02, .bd09:
            return "\(provider.displayName) coordinates (\(coordinateSystem.rawValue))"
        }
    }
}

struct ChinaPlaceResolverConfigurationStatus: Equatable {
    var backendProxyConfigured: Bool
    var amapConfigured: Bool
    var baiduConfigured: Bool
    var missingRequirements: [String]

    var configuredProviders: [String] {
        var providers: [String] = []
        if backendProxyConfigured { providers.append("backend_proxy") }
        if amapConfigured { providers.append("amap") }
        if baiduConfigured { providers.append("baidu") }
        return providers
    }

    var canResolveChinaPOI: Bool {
        backendProxyConfigured || amapConfigured || baiduConfigured
    }
}

enum ChinaPlaceResolverConfiguration {
    static func status(
        backendAPIBaseURL: String? = SAVEProductionConfig.URLConfigValue(for: ["SAVE_API_URL", "WANDERLY_API_URL"]),
        accessTokenProviderConfigured: Bool = true,
        amapWebServiceKey: String? = configuredProviderValue(for: "AMAP_WEB_SERVICE_KEY"),
        baiduMapWebServiceKey: String? = configuredProviderValue(for: "BAIDU_MAP_WEB_SERVICE_KEY")
    ) -> ChinaPlaceResolverConfigurationStatus {
        let backendProxyConfigured = backendAPIBaseURL != nil && accessTokenProviderConfigured
        let amapConfigured = normalizedProviderValue(amapWebServiceKey, placeholder: "AMAP_WEB_SERVICE_KEY") != nil
        let baiduConfigured = normalizedProviderValue(baiduMapWebServiceKey, placeholder: "BAIDU_MAP_WEB_SERVICE_KEY") != nil
        var missing: [String] = []
        if !backendProxyConfigured { missing.append("SAVE_API_URL with authenticated backend place resolver") }
        if !amapConfigured { missing.append("AMAP_WEB_SERVICE_KEY") }
        if !baiduConfigured { missing.append("BAIDU_MAP_WEB_SERVICE_KEY") }
        return ChinaPlaceResolverConfigurationStatus(
            backendProxyConfigured: backendProxyConfigured,
            amapConfigured: amapConfigured,
            baiduConfigured: baiduConfigured,
            missingRequirements: missing
        )
    }

    static func configuredProviderValue(for key: String, bundle: Bundle = .main) -> String? {
        if let value = normalizedProviderValue(ProcessInfo.processInfo.environment[key], placeholder: key) {
            return value
        }
        if let value = normalizedProviderValue(SAVEProductionConfig.keyFromPlist(key, bundle: bundle), placeholder: key) {
            return value
        }
        return nil
    }

    static func normalizedProviderValue(_ value: String?, placeholder: String) -> String? {
        guard let value = SAVEProductionConfig.normalizedConfigValue(value) else { return nil }
        return value.uppercased() == placeholder.uppercased() ? nil : value
    }
}

protocol PlaceResolverServiceProtocol {
    func searchPlace(query: String, near: CLLocationCoordinate2D?) async throws -> [PlaceProviderMatch]
}

protocol AmapPlaceSearchServiceProtocol {
    func searchPlace(query: String, near: CLLocationCoordinate2D?) async throws -> [PlaceProviderMatch]
}

protocol BaiduPlaceSearchServiceProtocol {
    func searchPlace(query: String, near: CLLocationCoordinate2D?) async throws -> [PlaceProviderMatch]
}

protocol BackendPlaceResolverServiceProtocol {
    func searchPlace(query: String, near: CLLocationCoordinate2D?) async throws -> [PlaceProviderMatch]
}

// MARK: - Errors

enum GooglePlacesError: LocalizedError {
    case apiKeyMissing
    case noResults
    case networkError(Error)
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .apiKeyMissing:
            return "Google Places key missing. Gemini is configured separately, but Refine + Save requires GOOGLE_PLACES_API_KEY."
        case .noResults: return "No matching places found"
        case .networkError(let error): return "Network error: \(error.localizedDescription)"
        case .apiError(let msg): return "Places API: \(msg)"
        }
    }
}

enum AmapPlaceSearchError: LocalizedError {
    case apiKeyMissing
    case noResults
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .apiKeyMissing:
            return "Amap Web Service key missing. China POI refinement requires AMAP_WEB_SERVICE_KEY."
        case .noResults:
            return "No matching Amap places found"
        case .apiError(let message):
            return "Amap API: \(message)"
        }
    }
}

enum BaiduPlaceSearchError: LocalizedError {
    case apiKeyMissing
    case noResults
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .apiKeyMissing:
            return "Baidu Maps Web Service key missing. China POI fallback requires BAIDU_MAP_WEB_SERVICE_KEY."
        case .noResults:
            return "No matching Baidu Maps places found"
        case .apiError(let message):
            return "Baidu Maps API: \(message)"
        }
    }
}

enum BackendPlaceResolverError: LocalizedError {
    case notConfigured
    case noResults
    case apiError(String)
}

// MARK: - Provider Resolver

final class PlaceResolverService: PlaceResolverServiceProtocol {
    static let shared = PlaceResolverService()

    private let googlePlacesService: GooglePlacesServiceProtocol
    private let amapPlaceSearchService: AmapPlaceSearchServiceProtocol
    private let baiduPlaceSearchService: BaiduPlaceSearchServiceProtocol
    private let backendPlaceResolverService: BackendPlaceResolverServiceProtocol

    init(
        googlePlacesService: GooglePlacesServiceProtocol = GooglePlacesService.shared,
        amapPlaceSearchService: AmapPlaceSearchServiceProtocol = AmapPlaceSearchService.shared,
        baiduPlaceSearchService: BaiduPlaceSearchServiceProtocol = BaiduPlaceSearchService.shared,
        backendPlaceResolverService: BackendPlaceResolverServiceProtocol = BackendPlaceResolverService.shared
    ) {
        self.googlePlacesService = googlePlacesService
        self.amapPlaceSearchService = amapPlaceSearchService
        self.baiduPlaceSearchService = baiduPlaceSearchService
        self.backendPlaceResolverService = backendPlaceResolverService
    }

    func searchPlace(query: String, near: CLLocationCoordinate2D?) async throws -> [PlaceProviderMatch] {
        var results: [PlaceProviderMatch] = []
        var seen = Set<String>()
        let shouldTryChinaProviders = Self.shouldTryChinaProviders(for: query)

        if shouldTryChinaProviders,
           let proxyMatches = try? await backendPlaceResolverService.searchPlace(query: query, near: near) {
            append(proxyMatches, to: &results, seen: &seen)
        }

        if shouldTryChinaProviders,
           let amapMatches = try? await amapPlaceSearchService.searchPlace(query: query, near: near) {
            append(amapMatches, to: &results, seen: &seen)
        }

        if shouldTryChinaProviders,
           let baiduMatches = try? await baiduPlaceSearchService.searchPlace(query: query, near: near) {
            append(baiduMatches, to: &results, seen: &seen)
        }

        if let googleMatches = try? await googlePlacesService.searchPlace(query: query, near: near) {
            append(googleMatches.map(\.providerMatch), to: &results, seen: &seen)
        }

        guard !results.isEmpty else { throw GooglePlacesError.noResults }
        return results
    }

    static func chinaProviderConfigurationStatus() -> ChinaPlaceResolverConfigurationStatus {
        ChinaPlaceResolverConfiguration.status()
    }

    private func append(_ matches: [PlaceProviderMatch], to results: inout [PlaceProviderMatch], seen: inout Set<String>) {
        for match in matches {
            let key = "\(match.provider.rawValue):\(match.id)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            results.append(match)
        }
    }

    private static func shouldTryChinaProviders(for query: String) -> Bool {
        query.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(Int(scalar.value)) ||
                (0x3400...0x4DBF).contains(Int(scalar.value))
        }
    }
}

private extension GooglePlaceMatch {
    var providerMatch: PlaceProviderMatch {
        PlaceProviderMatch(
            provider: .googlePlaces,
            id: id,
            name: name,
            address: address,
            latitude: latitude,
            longitude: longitude,
            rating: rating,
            reviewCount: reviewCount,
            priceLevel: priceLevel,
            types: types,
            coordinateSystem: .wgs84
        )
    }
}

// MARK: - Implementation

final class GooglePlacesService: GooglePlacesServiceProtocol {
    static let shared = GooglePlacesService()

    private let apiKey: String?

    init(apiKey: String? = nil) {
        self.apiKey = Self.normalizedAPIKey(
            apiKey
                ?? ProcessInfo.processInfo.environment["GOOGLE_PLACES_API_KEY"]
                ?? SAVEProductionConfig.keyFromPlist("GOOGLE_PLACES_API_KEY")
        )
    }

    private static func normalizedAPIKey(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }

        let placeholders: Set<String> = [
            "YOUR_KEY_HERE",
            "REPLACE_ME",
            "GOOGLE_PLACES_API_KEY"
        ]
        return placeholders.contains(trimmed.uppercased()) ? nil : trimmed
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

        return results.prefix(20).compactMap { result in
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
                reviewCount: result["user_ratings_total"] as? Int,
                priceLevel: result["price_level"] as? Int,
                photoReference: (result["photos"] as? [[String: Any]])?.first?["photo_reference"] as? String,
                types: result["types"] as? [String] ?? []
            )
        }
    }

    // MARK: - Place Details

    func getPlaceDetails(placeId: String) async throws -> GooglePlaceDetails {
        guard let apiKey, !apiKey.isEmpty else {
            throw GooglePlacesError.apiKeyMissing
        }

        let fields = "place_id,name,formatted_address,geometry,rating,price_level,opening_hours,formatted_phone_number,website,photos,types"
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
            photoReferences: photos?.compactMap { $0["photo_reference"] as? String },
            types: result["types"] as? [String] ?? []
        )
    }

    // MARK: - Photo URL

    func photoURL(reference: String, maxWidth: Int = 400) -> URL? {
        guard let apiKey else { return nil }
        return URL(string: "https://maps.googleapis.com/maps/api/place/photo?maxwidth=\(maxWidth)&photo_reference=\(reference)&key=\(apiKey)")
    }
}

// MARK: - Amap

final class AmapPlaceSearchService: AmapPlaceSearchServiceProtocol {
    static let shared = AmapPlaceSearchService()

    private let apiKey: String?

    init(apiKey: String? = nil) {
        self.apiKey = Self.normalizedAPIKey(
            apiKey
                ?? ChinaPlaceResolverConfiguration.configuredProviderValue(for: "AMAP_WEB_SERVICE_KEY")
        )
    }

    func searchPlace(query: String, near: CLLocationCoordinate2D?) async throws -> [PlaceProviderMatch] {
        guard let apiKey, !apiKey.isEmpty else {
            throw AmapPlaceSearchError.apiKeyMissing
        }

        var components = URLComponents(string: "https://restapi.amap.com/v3/place/text")
        var queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "keywords", value: query),
            URLQueryItem(name: "types", value: "050000"),
            URLQueryItem(name: "offset", value: "20"),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "extensions", value: "all")
        ]
        if let city = Self.cityHint(in: query) {
            queryItems.append(URLQueryItem(name: "city", value: city))
            queryItems.append(URLQueryItem(name: "citylimit", value: "true"))
        }
        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw AmapPlaceSearchError.noResults
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard json?["status"] as? String == "1" else {
            let message = (json?["info"] as? String) ?? (json?["infocode"] as? String) ?? "unknown"
            throw AmapPlaceSearchError.apiError(message)
        }

        guard let pois = json?["pois"] as? [[String: Any]], !pois.isEmpty else {
            throw AmapPlaceSearchError.noResults
        }

        return pois.compactMap { poi in
            guard let id = poi["id"] as? String,
                  let name = poi["name"] as? String,
                  let location = poi["location"] as? String,
                  let coordinate = Self.coordinate(from: location) else { return nil }

            let address = [
                poi["pname"] as? String,
                poi["cityname"] as? String,
                poi["adname"] as? String,
                Self.stringValue(poi["address"])
            ]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .reduce(into: [String]()) { result, value in
                    if !result.contains(value) { result.append(value) }
                }
                .joined(separator: "")

            let bizExt = poi["biz_ext"] as? [String: Any]
            return PlaceProviderMatch(
                provider: .amap,
                id: id,
                name: name,
                address: address,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                rating: Self.doubleValue(bizExt?["rating"]),
                reviewCount: nil,
                priceLevel: nil,
                types: [Self.stringValue(poi["type"]), Self.stringValue(poi["typecode"])].compactMap { $0 },
                coordinateSystem: .gcj02
            )
        }
    }

    private static func coordinate(from value: String) -> CLLocationCoordinate2D? {
        let parts = value.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.count == 2,
              let longitude = Double(parts[0]),
              let latitude = Double(parts[1]) else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private static func cityHint(in query: String) -> String? {
        [
            "北京", "上海", "广州", "深圳", "杭州", "成都", "重庆", "南京",
            "苏州", "西安", "武汉", "长沙", "厦门", "青岛", "天津", "宁波"
        ].first { query.contains($0) }
    }

    private static func normalizedAPIKey(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }

        let placeholders: Set<String> = [
            "YOUR_KEY_HERE",
            "REPLACE_ME",
            "AMAP_WEB_SERVICE_KEY"
        ]
        return placeholders.contains(trimmed.uppercased()) ? nil : trimmed
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let array = value as? [Any] {
            return array.compactMap { $0 as? String }.joined(separator: " ")
        }
        return nil
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let string = value as? String { return Double(string) }
        return nil
    }
}

// MARK: - Baidu Maps

final class BaiduPlaceSearchService: BaiduPlaceSearchServiceProtocol {
    static let shared = BaiduPlaceSearchService()

    private let apiKey: String?

    init(apiKey: String? = nil) {
        self.apiKey = Self.normalizedAPIKey(
            apiKey
                ?? ChinaPlaceResolverConfiguration.configuredProviderValue(for: "BAIDU_MAP_WEB_SERVICE_KEY")
        )
    }

    func searchPlace(query: String, near: CLLocationCoordinate2D?) async throws -> [PlaceProviderMatch] {
        guard let apiKey, !apiKey.isEmpty else {
            throw BaiduPlaceSearchError.apiKeyMissing
        }

        var components = URLComponents(string: "https://api.map.baidu.com/place/v2/search")
        var queryItems = [
            URLQueryItem(name: "ak", value: apiKey),
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "tag", value: "美食"),
            URLQueryItem(name: "region", value: Self.cityHint(in: query) ?? "全国"),
            URLQueryItem(name: "city_limit", value: Self.cityHint(in: query) == nil ? "false" : "true"),
            URLQueryItem(name: "output", value: "json"),
            URLQueryItem(name: "scope", value: "2"),
            URLQueryItem(name: "page_size", value: "20")
        ]
        if let near {
            queryItems.append(URLQueryItem(name: "location", value: "\(near.latitude),\(near.longitude)"))
            queryItems.append(URLQueryItem(name: "radius", value: "5000"))
        }
        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw BaiduPlaceSearchError.noResults
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let status = Self.intValue(json?["status"]) ?? -1
        guard status == 0 else {
            let message = Self.stringValue(json?["message"]) ?? "status \(status)"
            throw BaiduPlaceSearchError.apiError(message)
        }

        guard let results = json?["results"] as? [[String: Any]], !results.isEmpty else {
            throw BaiduPlaceSearchError.noResults
        }

        return results.compactMap { result in
            guard let name = Self.stringValue(result["name"]),
                  let location = result["location"] as? [String: Any],
                  let latitude = Self.doubleValue(location["lat"]),
                  let longitude = Self.doubleValue(location["lng"]) else { return nil }
            let id = Self.stringValue(result["uid"]) ?? "baidu-\(name)-\(latitude)-\(longitude)"
            let address = [
                Self.stringValue(result["province"]),
                Self.stringValue(result["city"]),
                Self.stringValue(result["area"]),
                Self.stringValue(result["address"])
            ]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .reduce(into: [String]()) { values, value in
                    if !values.contains(value) { values.append(value) }
                }
                .joined(separator: "")
            let detailInfo = result["detail_info"] as? [String: Any]
            return PlaceProviderMatch(
                provider: .baidu,
                id: id,
                name: name,
                address: address,
                latitude: latitude,
                longitude: longitude,
                rating: Self.doubleValue(detailInfo?["overall_rating"]),
                reviewCount: Self.intValue(detailInfo?["comment_num"]),
                priceLevel: nil,
                types: [Self.stringValue(result["tag"])].compactMap { $0 },
                coordinateSystem: .bd09
            )
        }
    }

    private static func cityHint(in query: String) -> String? {
        [
            "北京", "上海", "广州", "深圳", "杭州", "成都", "重庆", "南京",
            "苏州", "西安", "武汉", "长沙", "厦门", "青岛", "天津", "宁波"
        ].first { query.contains($0) }
    }

    private static func normalizedAPIKey(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        let placeholders: Set<String> = ["YOUR_KEY_HERE", "REPLACE_ME", "BAIDU_MAP_WEB_SERVICE_KEY"]
        return placeholders.contains(trimmed.uppercased()) ? nil : trimmed
    }

    fileprivate static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let array = value as? [Any] { return array.compactMap { $0 as? String }.joined(separator: " ") }
        return nil
    }

    fileprivate static func doubleValue(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let string = value as? String { return Double(string) }
        return nil
    }

    fileprivate static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let double = value as? Double { return Int(double) }
        if let string = value as? String { return Int(string) }
        return nil
    }
}

// MARK: - Backend place resolver proxy

final class BackendPlaceResolverService: BackendPlaceResolverServiceProtocol {
    static let shared = BackendPlaceResolverService()

    private let apiBaseURL: String?
    private let accessTokenProvider: (() async throws -> String)?

    init(
        apiBaseURL: String? = SAVEProductionConfig.URLConfigValue(for: ["SAVE_API_URL", "WANDERLY_API_URL"]),
        accessTokenProvider: (() async throws -> String)? = {
            try await PrivyAuthService.shared.accessToken()
        }
    ) {
        self.apiBaseURL = apiBaseURL?.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.accessTokenProvider = accessTokenProvider
    }

    func searchPlace(query: String, near: CLLocationCoordinate2D?) async throws -> [PlaceProviderMatch] {
        guard let apiBaseURL, !apiBaseURL.isEmpty,
              let endpoint = URL(string: "\(apiBaseURL)/place-resolve") else {
            throw BackendPlaceResolverError.notConfigured
        }
        guard let accessTokenProvider else { throw BackendPlaceResolverError.notConfigured }

        var body: [String: Any] = ["query": query, "provider": "china"]
        if let near {
            body["near"] = ["latitude": near.latitude, "longitude": near.longitude]
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(try await accessTokenProvider())", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw BackendPlaceResolverError.apiError(String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)")
        }
        let decoded = try JSONDecoder().decode(BackendPlaceResolveResponse.self, from: data)
        guard !decoded.matches.isEmpty else { throw BackendPlaceResolverError.noResults }
        return decoded.matches
    }
}

private struct BackendPlaceResolveResponse: Codable {
    var matches: [PlaceProviderMatch]
}

// MARK: - China map deep-link parser

struct ChinaMapDeepLinkParser {
    static func match(from urlString: String) -> PlaceProviderMatch? {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host?.lowercased() else { return nil }
        if host.contains("amap.com") || url.scheme?.lowercased() == "iosamap" || url.scheme?.lowercased() == "amapuri" {
            return amapMatch(from: url)
        }
        if host.contains("baidu.com") || url.scheme?.lowercased() == "baidumap" {
            return baiduMatch(from: url)
        }
        return nil
    }

    private static func amapMatch(from url: URL) -> PlaceProviderMatch? {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name.lowercased(), $0.value ?? "") })
        let name = query["name"] ?? query["poiname"] ?? query["keywords"] ?? titleFromPath(url) ?? "Amap place"
        let address = query["address"] ?? query["addr"] ?? ""
        let coordinate = coordinateFromLngLat(query["position"] ?? query["location"] ?? query["lnglat"])
        guard let coordinate else { return nil }
        return PlaceProviderMatch(
            provider: .amap,
            id: query["poiid"] ?? "amap-url-\(coordinate.latitude)-\(coordinate.longitude)",
            name: decoded(name),
            address: decoded(address),
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            rating: nil,
            reviewCount: nil,
            priceLevel: nil,
            types: [],
            coordinateSystem: .gcj02
        )
    }

    private static func baiduMatch(from url: URL) -> PlaceProviderMatch? {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name.lowercased(), $0.value ?? "") })
        let name = query["title"] ?? query["name"] ?? query["query"] ?? titleFromPath(url) ?? "Baidu Maps place"
        let address = query["content"] ?? query["address"] ?? ""
        let coordinate = coordinateFromLatLng(query["location"] ?? query["center"]) ?? coordinateFromLngLat(query["coord"])
        guard let coordinate else { return nil }
        return PlaceProviderMatch(
            provider: .baidu,
            id: query["uid"] ?? "baidu-url-\(coordinate.latitude)-\(coordinate.longitude)",
            name: decoded(name),
            address: decoded(address),
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            rating: nil,
            reviewCount: nil,
            priceLevel: nil,
            types: [],
            coordinateSystem: .bd09
        )
    }

    private static func coordinateFromLngLat(_ value: String?) -> CLLocationCoordinate2D? {
        guard let parts = value?.split(separator: ",").map({ String($0).trimmingCharacters(in: .whitespacesAndNewlines) }),
              parts.count == 2,
              let longitude = Double(parts[0]),
              let latitude = Double(parts[1]) else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private static func coordinateFromLatLng(_ value: String?) -> CLLocationCoordinate2D? {
        guard let parts = value?.split(separator: ",").map({ String($0).trimmingCharacters(in: .whitespacesAndNewlines) }),
              parts.count == 2,
              let latitude = Double(parts[0]),
              let longitude = Double(parts[1]) else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private static func titleFromPath(_ url: URL) -> String? {
        url.pathComponents.reversed().first { component in
            component != "/" && component.count > 1 && component.rangeOfCharacter(from: .decimalDigits.inverted) != nil
        }.map(decoded)
    }

    private static func decoded(_ value: String) -> String {
        value.removingPercentEncoding ?? value
    }
}

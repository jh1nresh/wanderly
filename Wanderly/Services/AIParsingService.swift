import Foundation

// MARK: - Protocol

protocol AIParsingServiceProtocol {
    func parseURL(_ url: URL) async throws -> ParsedPlaceResult
    func parseImage(_ imageData: Data) async throws -> ParsedPlaceResult
}

// MARK: - Parsed Result

struct ParsedPlaceResult: Codable {
    var placeName: String?
    var address: String?
    var category: PlaceCategory?
    var dishes: [String]?
    var priceRange: String?
    var recommender: String?
    var latitude: Double?
    var longitude: Double?
    var confidence: Double
}

// MARK: - Errors

enum AIParsingError: LocalizedError {
    case invalidResponse
    case apiKeyMissing
    case networkError(Error)
    case parsingFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from AI service"
        case .apiKeyMissing: return "Gemini API key not configured"
        case .networkError(let error): return "Network error: \(error.localizedDescription)"
        case .parsingFailed(let reason): return "Parsing failed: \(reason)"
        }
    }
}

// MARK: - Gemini Implementation

final class AIParsingService: AIParsingServiceProtocol {
    static let shared = AIParsingService()

    private let apiKey: String?

    init(apiKey: String? = nil) {
        let resolved = apiKey
            ?? ProcessInfo.processInfo.environment["GEMINI_API_KEY"]
            ?? Self.keyFromPlist("GEMINI_API_KEY")
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

    // MARK: - Parse URL

    func parseURL(_ url: URL) async throws -> ParsedPlaceResult {
        guard let apiKey, !apiKey.isEmpty else {
            throw AIParsingError.apiKeyMissing
        }

        // Step 1: Fetch OpenGraph metadata from URL
        let metadata = await fetchOpenGraphMetadata(from: url)

        // Step 2: Send metadata + URL to Gemini for parsing
        let prompt = """
        Extract place information from this shared content.

        URL: \(url.absoluteString)
        Page title: \(metadata.title ?? "unknown")
        Page description: \(metadata.description ?? "unknown")
        Site name: \(metadata.siteName ?? "unknown")

        Respond ONLY with a valid JSON object:
        {
          "placeName": "Name of the place",
          "address": "Full address",
          "category": "food" | "cafe" | "bar" | "attraction" | "stay" | "shopping",
          "dishes": ["dish1", "dish2"],
          "priceRange": "$$",
          "recommender": "@username or null",
          "latitude": 0.0,
          "longitude": 0.0,
          "confidence": 0.0 to 1.0
        }

        If you can identify the place, set confidence high (0.7+).
        If uncertain, set confidence low (<0.5) and provide your best guess.
        """

        return try await callGemini(prompt: prompt)
    }

    // MARK: - Parse Image

    func parseImage(_ imageData: Data) async throws -> ParsedPlaceResult {
        guard let apiKey, !apiKey.isEmpty else {
            throw AIParsingError.apiKeyMissing
        }

        let base64 = imageData.base64EncodedString()

        let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=\(apiKey)")!

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let prompt = """
        Look at this image and extract place/restaurant information.
        Respond ONLY with a valid JSON object:
        {
          "placeName": "Name",
          "address": "Address if visible",
          "category": "food" | "cafe" | "bar" | "attraction" | "stay" | "shopping",
          "dishes": ["any visible dishes"],
          "priceRange": "$$ or null",
          "confidence": 0.0 to 1.0
        }
        """

        let body: [String: Any] = [
            "contents": [[
                "parts": [
                    ["text": prompt],
                    ["inline_data": ["mime_type": "image/jpeg", "data": base64]]
                ]
            ]],
            "generationConfig": ["temperature": 0.2, "maxOutputTokens": 512]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw AIParsingError.parsingFailed("Gemini API error \(code)")
        }

        return try parseGeminiResponse(data)
    }

    // MARK: - Private

    private func callGemini(prompt: String) async throws -> ParsedPlaceResult {
        guard let apiKey else { throw AIParsingError.apiKeyMissing }

        let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=\(apiKey)")!

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": ["temperature": 0.2, "maxOutputTokens": 512]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw AIParsingError.parsingFailed("Gemini API error \(code)")
        }

        return try parseGeminiResponse(data)
    }

    private func parseGeminiResponse(_ data: Data) throws -> ParsedPlaceResult {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let candidates = json?["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            throw AIParsingError.invalidResponse
        }

        // Extract JSON
        var jsonString = text
        if let start = text.range(of: "{"), let end = text.range(of: "}", options: .backwards) {
            jsonString = String(text[start.lowerBound...end.upperBound])
        }
        guard let jsonData = jsonString.data(using: .utf8),
              let dict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw AIParsingError.invalidResponse
        }

        let categoryStr = dict["category"] as? String ?? "food"

        return ParsedPlaceResult(
            placeName: dict["placeName"] as? String,
            address: dict["address"] as? String,
            category: PlaceCategory(rawValue: categoryStr),
            dishes: dict["dishes"] as? [String],
            priceRange: dict["priceRange"] as? String,
            recommender: dict["recommender"] as? String,
            latitude: dict["latitude"] as? Double,
            longitude: dict["longitude"] as? Double,
            confidence: dict["confidence"] as? Double ?? 0.5
        )
    }

    // MARK: - OpenGraph Metadata

    private struct OGMetadata {
        var title: String?
        var description: String?
        var siteName: String?
    }

    private func fetchOpenGraphMetadata(from url: URL) async -> OGMetadata {
        var metadata = OGMetadata()

        do {
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 5

            let (data, _) = try await URLSession.shared.data(for: request)
            guard let html = String(data: data, encoding: .utf8) else { return metadata }

            metadata.title = extractMeta(from: html, property: "og:title")
                ?? extractTag(from: html, tag: "title")
            metadata.description = extractMeta(from: html, property: "og:description")
                ?? extractMeta(from: html, name: "description")
            metadata.siteName = extractMeta(from: html, property: "og:site_name")
        } catch {
            // Silently fail — Gemini can still work with just the URL
        }

        return metadata
    }

    private func extractMeta(from html: String, property: String) -> String? {
        let pattern = #"<meta[^>]*property="\#(property)"[^>]*content="([^"]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else { return nil }
        return String(html[range])
    }

    private func extractMeta(from html: String, name: String) -> String? {
        let pattern = #"<meta[^>]*name="\#(name)"[^>]*content="([^"]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else { return nil }
        return String(html[range])
    }

    private func extractTag(from html: String, tag: String) -> String? {
        let pattern = "<\(tag)>([^<]*)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else { return nil }
        return String(html[range])
    }
}

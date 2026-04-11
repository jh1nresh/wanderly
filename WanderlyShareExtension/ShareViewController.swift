import UIKit
import SwiftUI
import UniformTypeIdentifiers

class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        let hostingController = UIHostingController(rootView: ShareExtensionView(
            extensionContext: extensionContext
        ))
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        hostingController.didMove(toParent: self)
    }
}

// MARK: - Parsed Place Model

struct ParsedPlace {
    var name: String
    var address: String
    var category: String
    var iconName: String
    var latitude: Double
    var longitude: Double
    var dishes: [String]
    var priceRange: String?
}

// MARK: - Share Extension SwiftUI View

struct ShareExtensionView: View {
    weak var extensionContext: NSExtensionContext?
    @State private var sharedURL: String = ""
    @State private var sharedText: String = ""
    @State private var parsedPlace: ParsedPlace?
    @State private var isParsing = true
    @State private var isSaved = false
    @State private var parseError: String?
    @State private var selectedCategory: String = "food"

    private let categories = ["food", "cafe", "bar", "attraction", "stay", "shopping"]

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                if isParsing {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                            .tint(Color(hex: "C75B39"))

                        Text("AI is parsing the shared content...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxHeight: .infinity)
                } else if isSaved {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 56))
                            .foregroundColor(Color(hex: "A8B5A0"))

                        Text("Saved to Wanderly!")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(Color(hex: "2C2C2E"))

                        Text("Open the app to see it on your map.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxHeight: .infinity)
                } else if let error = parseError {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                            .foregroundColor(Color(hex: "C75B39"))
                        Text("Couldn't parse this content")
                            .font(.headline)
                            .foregroundColor(Color(hex: "2C2C2E"))
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxHeight: .infinity)
                    .padding()
                } else if let place = parsedPlace {
                    placePreview(place)
                }
            }
            .background(Color(hex: "FFF8F0"))
            .navigationTitle("Save Place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        extensionContext?.cancelRequest(withError: NSError(domain: "com.wanderly", code: 0))
                    }
                }
            }
        }
        .task {
            await extractAndParse()
        }
    }

    // MARK: - Place Preview

    private func placePreview(_ place: ParsedPlace) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Parsed place card
            VStack(alignment: .leading, spacing: 8) {
                Text("Detected Place")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    Image(systemName: iconForCategory(selectedCategory))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Color(hex: "C75B39"))
                        .cornerRadius(10)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.name)
                            .font(.headline)
                            .foregroundColor(Color(hex: "2C2C2E"))
                        Text(place.address)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if let price = place.priceRange {
                        Text(price)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Dishes
                if !place.dishes.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(place.dishes, id: \.self) { dish in
                                Text(dish)
                                    .font(.caption2)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color(hex: "C75B39").opacity(0.1))
                                    .cornerRadius(8)
                            }
                        }
                    }
                }
            }
            .padding()
            .background(Color(hex: "FFF8F0"))
            .cornerRadius(16)

            // Category selector
            Text("Category")
                .font(.caption)
                .foregroundColor(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories, id: \.self) { cat in
                        Button(action: { selectedCategory = cat }) {
                            HStack(spacing: 4) {
                                Image(systemName: iconForCategory(cat))
                                    .font(.caption2)
                                Text(cat.capitalized)
                            }
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(cat == selectedCategory ? Color(hex: "C75B39") : Color(hex: "C75B39").opacity(0.1))
                            .foregroundColor(cat == selectedCategory ? .white : Color(hex: "C75B39"))
                            .cornerRadius(16)
                        }
                    }
                }
            }

            Spacer()

            // Save button
            Button(action: savePlace) {
                Text("Save to Map")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(hex: "C75B39"))
                    .cornerRadius(16)
            }
        }
        .padding()
    }

    // MARK: - Extract & Parse

    private func extractAndParse() async {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            parseError = "No content to parse"
            isParsing = false
            return
        }

        // Extract URL or text
        for item in items {
            guard let attachments = item.attachments else { continue }
            for attachment in attachments {
                if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let url = try? await attachment.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                        sharedURL = url.absoluteString
                    }
                } else if attachment.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
                    if let text = try? await attachment.loadItem(forTypeIdentifier: UTType.text.identifier) as? String {
                        sharedText = text
                    }
                }
            }
        }

        let content = sharedURL.isEmpty ? sharedText : sharedURL
        guard !content.isEmpty else {
            parseError = "No URL or text found in shared content"
            isParsing = false
            return
        }

        // Parse with Gemini
        do {
            parsedPlace = try await parseWithGemini(content: content)
            selectedCategory = parsedPlace?.category ?? "food"
        } catch {
            parseError = error.localizedDescription
        }
        isParsing = false
    }

    // MARK: - Gemini Parsing

    private func parseWithGemini(content: String) async throws -> ParsedPlace {
        guard let apiKey = geminiAPIKey(), !apiKey.isEmpty else {
            throw NSError(domain: "wanderly", code: 1, userInfo: [NSLocalizedDescriptionKey: "GEMINI_API_KEY not configured"])
        }

        let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=\(apiKey)")!

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let prompt = """
        Extract place information from this shared content. Respond ONLY with a valid JSON object, no markdown.

        Content: \(content)

        Response schema:
        {
          "name": "Place Name",
          "address": "Full address",
          "category": "food" | "cafe" | "bar" | "attraction" | "stay" | "shopping",
          "latitude": 0.0,
          "longitude": 0.0,
          "dishes": ["dish1", "dish2"],
          "priceRange": "$$"
        }

        Rules:
        - Extract the place name, address, and category from the URL or text
        - If it's a restaurant/food URL, extract recommended dishes
        - Estimate lat/lng from the address
        - If you can't determine something, use reasonable defaults
        - category must be one of: food, cafe, bar, attraction, stay, shopping
        """

        let body: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": ["temperature": 0.2, "maxOutputTokens": 512]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw NSError(domain: "wanderly", code: code, userInfo: [NSLocalizedDescriptionKey: "Gemini API error \(code)"])
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let candidates = json?["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            throw NSError(domain: "wanderly", code: 2, userInfo: [NSLocalizedDescriptionKey: "Empty AI response"])
        }

        // Parse JSON from response
        var jsonString = text
        if let start = text.range(of: "{"), let end = text.range(of: "}", options: .backwards) {
            jsonString = String(text[start.lowerBound...end.upperBound])
        }
        guard let jsonData = jsonString.data(using: .utf8),
              let dict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw NSError(domain: "wanderly", code: 3, userInfo: [NSLocalizedDescriptionKey: "Couldn't parse AI response"])
        }

        return ParsedPlace(
            name: dict["name"] as? String ?? "Unknown Place",
            address: dict["address"] as? String ?? "",
            category: dict["category"] as? String ?? "food",
            iconName: iconForCategory(dict["category"] as? String ?? "food"),
            latitude: dict["latitude"] as? Double ?? 0,
            longitude: dict["longitude"] as? Double ?? 0,
            dishes: dict["dishes"] as? [String] ?? [],
            priceRange: dict["priceRange"] as? String
        )
    }

    private func geminiAPIKey() -> String? {
        // Try environment variable first, then Secrets.plist in shared App Group
        if let key = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !key.isEmpty {
            return key
        }
        // Try reading from main app bundle's Secrets.plist via App Group
        // For now, try the extension's own bundle
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String],
              let value = dict["GEMINI_API_KEY"],
              value != "YOUR_KEY_HERE" else { return nil }
        return value
    }

    // MARK: - Save

    private func savePlace() {
        // Save to UserDefaults in shared App Group for main app to pick up
        // For now, use a simple shared container
        if let place = parsedPlace {
            let placeData: [String: Any] = [
                "name": place.name,
                "address": place.address,
                "category": selectedCategory,
                "latitude": place.latitude,
                "longitude": place.longitude,
                "dishes": place.dishes,
                "priceRange": place.priceRange ?? "",
                "savedAt": Date().timeIntervalSince1970
            ]

            // Store in shared UserDefaults (App Group needed for production)
            var pending = UserDefaults.standard.array(forKey: "pendingPlaces") as? [[String: Any]] ?? []
            pending.append(placeData)
            UserDefaults.standard.set(pending, forKey: "pendingPlaces")
        }

        isSaved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            extensionContext?.completeRequest(returningItems: nil)
        }
    }

    // MARK: - Helpers

    private func iconForCategory(_ category: String) -> String {
        switch category {
        case "food": return "fork.knife"
        case "cafe": return "cup.and.saucer.fill"
        case "bar": return "wineglass.fill"
        case "attraction": return "star.fill"
        case "stay": return "bed.double.fill"
        case "shopping": return "bag.fill"
        default: return "mappin"
        }
    }
}

// MARK: - Hex Color (standalone for extension target)

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

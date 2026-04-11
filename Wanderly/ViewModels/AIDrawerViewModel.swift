import Foundation

@MainActor
final class AIDrawerViewModel: ObservableObject {

    enum DrawerState: Equatable {
        case idle
        case loading
        case displaying(WanderlyAIResponse)
        case placeDetail(Place)
        case error(String)
    }

    @Published var drawerState: DrawerState = .idle
    @Published var query = ""
    @Published var mapAction: MapActionData?
    @Published var chatHistory: [ChatEntry] = []
    @Published var showPlaceList = false

    struct ChatEntry: Identifiable, Equatable {
        let id = UUID()
        let query: String
        let timestamp: Date
    }

    // TODO: inject from shared data layer; for now mirrors mock
    var places: [Place] = Place.mockList

    private let aiService: WanderlyAIService

    /// Multi-turn conversation context for the current session.
    private var conversationTurns: [ConversationTurn] = []

    init(aiService: WanderlyAIService = .shared) {
        self.aiService = aiService
    }

    func submit() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        drawerState = .loading
        mapAction = nil

        // Save to sidebar history (avoid duplicates at top)
        if chatHistory.first?.query != trimmed {
            chatHistory.insert(ChatEntry(query: trimmed, timestamp: Date()), at: 0)
            if chatHistory.count > 20 { chatHistory.removeLast() }
        }

        do {
            let response = try await aiService.query(trimmed, places: places, conversationHistory: conversationTurns)
            drawerState = .displaying(response)
            mapAction = response.mapAction

            // Save this turn for follow-up context
            let responseJSON = aiService.encodeResponse(response)
            conversationTurns.append(ConversationTurn(userMessage: trimmed, assistantResponse: responseJSON))

            // Keep last 5 turns to avoid token limits
            if conversationTurns.count > 5 {
                conversationTurns.removeFirst()
            }
        } catch {
            drawerState = .error(error.localizedDescription)
        }
    }

    func showPlace(_ place: Place) {
        drawerState = .placeDetail(place)
        mapAction = MapActionData(type: .focusRegion, placeIds: nil,
                                  lat: place.latitude, lng: place.longitude, span: 0.01)
    }

    func reset() {
        drawerState = .idle
        query = ""
        conversationTurns = []
        mapAction = MapActionData(type: .resetPins, placeIds: nil, lat: nil, lng: nil, span: nil)
    }

    func startNewConversation() {
        drawerState = .idle
        query = ""
        conversationTurns = []
    }

    func resolvePlaces(from ids: [String]) -> [Place] {
        let uuids = Set(ids.compactMap { UUID(uuidString: $0) })
        return places.filter { uuids.contains($0.id) }
    }

    func resolvePlace(id: String?) -> Place? {
        guard let id, let uuid = UUID(uuidString: id) else { return nil }
        return places.first { $0.id == uuid }
    }
}

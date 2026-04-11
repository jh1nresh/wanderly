import Foundation
import MapKit

// MARK: - AI Response (domain model)

struct WanderlyAIResponse: Equatable {
    let componentType: ComponentType
    let title: String?
    let placeIds: [String]
    let navigationPlaceId: String?
    let transportMode: TransportMode
    let itineraryDays: [ItineraryDay]
    let messageText: String?
    let mapAction: MapActionData?
    let aiMessage: String?

    enum ComponentType: String, Codable, Equatable {
        case placeList, navigationCard, tripItinerary, message
    }

    enum TransportMode: String, Codable, Equatable {
        case walking, transit, driving

        var mapsKey: String {
            switch self {
            case .walking: return MKLaunchOptionsDirectionsModeWalking
            case .transit: return MKLaunchOptionsDirectionsModeTransit
            case .driving: return MKLaunchOptionsDirectionsModeDriving
            }
        }
    }
}

// MARK: - Map Action

struct MapActionData: Codable, Equatable {
    let type: ActionType
    let placeIds: [String]?
    let lat: Double?
    let lng: Double?
    let span: Double?

    enum ActionType: String, Codable, Equatable {
        case filterPins, focusRegion, showRoute, resetPins
    }
}

// MARK: - Itinerary

struct ItineraryDay: Identifiable, Equatable {
    let dayNumber: Int
    let label: String?
    let stops: [ItineraryStop]
    var id: Int { dayNumber }
}

struct ItineraryStop: Identifiable, Equatable {
    let id: UUID
    let placeId: String?
    let placeName: String
    let time: String?
    let duration: Int?
    let note: String?
}

// MARK: - Codable DTOs (what Claude actually returns)

struct WanderlyAIResponseDTO: Codable {
    let componentType: String
    let title: String?
    let placeIds: [String]?
    let navigationPlaceId: String?
    let transportMode: String?
    let itineraryDays: [ItineraryDayDTO]?
    let messageText: String?
    let mapAction: MapActionData?
    let aiMessage: String?

    func toResponse() -> WanderlyAIResponse {
        WanderlyAIResponse(
            componentType: WanderlyAIResponse.ComponentType(rawValue: componentType) ?? .message,
            title: title,
            placeIds: placeIds ?? [],
            navigationPlaceId: navigationPlaceId,
            transportMode: WanderlyAIResponse.TransportMode(rawValue: transportMode ?? "walking") ?? .walking,
            itineraryDays: (itineraryDays ?? []).map { $0.toModel() },
            messageText: messageText,
            mapAction: mapAction,
            aiMessage: aiMessage
        )
    }
}

struct ItineraryDayDTO: Codable {
    let dayNumber: Int
    let label: String?
    let stops: [ItineraryStopDTO]

    func toModel() -> ItineraryDay {
        ItineraryDay(dayNumber: dayNumber, label: label, stops: stops.map { $0.toModel() })
    }
}

struct ItineraryStopDTO: Codable {
    let placeId: String?
    let placeName: String
    let time: String?
    let duration: Int?
    let note: String?

    func toModel() -> ItineraryStop {
        ItineraryStop(id: UUID(), placeId: placeId, placeName: placeName, time: time, duration: duration, note: note)
    }
}

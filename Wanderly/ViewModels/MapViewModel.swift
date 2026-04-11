import Foundation
import MapKit
import SwiftUI

@MainActor
final class MapViewModel: ObservableObject {
    @Published var places: [Place] = Place.mockList
    @Published var selectedPlace: Place?
    @Published var cameraPosition: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    ))
    @Published var selectedCategories: Set<PlaceCategory> = []
    @Published var activeFilter: Set<UUID>?       // nil = show all
    @Published var routeCoordinates: [CLLocationCoordinate2D] = []
    @Published var isLoading = false
    @Published var calculatedRoute: MKPolyline?

    private let supabaseService: SupabaseServiceProtocol
    private let authService: PrivyAuthService

    init(supabaseService: SupabaseServiceProtocol = SupabaseService.shared) {
        self.supabaseService = supabaseService
        self.authService = PrivyAuthService.shared
    }

    // MARK: - Computed

    var filteredPlaces: [Place] {
        var result = places
        if !selectedCategories.isEmpty {
            result = result.filter { selectedCategories.contains($0.category) }
        }
        if let filter = activeFilter {
            result = result.filter { filter.contains($0.id) }
        }
        return result
    }

    var routePolyline: MKPolyline? {
        guard let polyline = calculatedRoute else {
            // Fallback to straight lines if no calculated route
            guard routeCoordinates.count >= 2 else { return nil }
            return MKPolyline(coordinates: routeCoordinates, count: routeCoordinates.count)
        }
        return polyline
    }

    // MARK: - Actions

    func loadPlaces() async {
        guard let userId = authService.currentUserId else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            places = try await supabaseService.fetchPlaces(for: userId)
        } catch {
            print("MapViewModel: failed to load places: \(error)")
        }
    }

    func selectPlace(_ place: Place) {
        selectedPlace = place
    }

    func toggleCategory(_ category: PlaceCategory) {
        if selectedCategories.contains(category) {
            selectedCategories.remove(category)
        } else {
            selectedCategories.insert(category)
        }
    }

    // MARK: - Apply AI map action

    func apply(_ action: MapActionData) {
        switch action.type {
        case .filterPins:
            let ids = Set((action.placeIds ?? []).compactMap { UUID(uuidString: $0) })
            activeFilter = ids.isEmpty ? nil : ids

        case .focusRegion:
            guard let lat = action.lat, let lng = action.lng else { return }
            let span = action.span ?? 0.03
            cameraPosition = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
            ))

        case .showRoute:
            let orderedIds = action.placeIds ?? []
            let idToPlace = Dictionary(uniqueKeysWithValues: places.map { ($0.id.uuidString, $0) })
            let routePlaces = orderedIds.compactMap { idToPlace[$0] }
            routeCoordinates = routePlaces.map { $0.coordinate }
            activeFilter = Set(routePlaces.map { $0.id })
            if let region = regionContaining(routePlaces) {
                cameraPosition = .region(region)
            }
            Task { await calculateRoute(for: routePlaces) }

        case .resetPins:
            activeFilter = nil
            routeCoordinates = []
            calculatedRoute = nil
        }
    }

    // MARK: - Route Calculation

    private func calculateRoute(for places: [Place]) async {
        guard places.count >= 2 else { return }
        calculatedRoute = nil

        var allCoordinates: [CLLocationCoordinate2D] = []

        // Calculate route segments between consecutive places
        for i in 0..<(places.count - 1) {
            let source = MKMapItem(placemark: MKPlacemark(coordinate: places[i].coordinate))
            let destination = MKMapItem(placemark: MKPlacemark(coordinate: places[i + 1].coordinate))

            let request = MKDirections.Request()
            request.source = source
            request.destination = destination
            request.transportType = .walking

            do {
                let directions = MKDirections(request: request)
                let response = try await directions.calculate()
                if let route = response.routes.first {
                    let points = route.polyline.points()
                    let count = route.polyline.pointCount
                    for j in 0..<count {
                        allCoordinates.append(points[j].coordinate)
                    }
                }
            } catch {
                print("Route calculation failed for segment \(i): \(error)")
                // Fallback: add straight line for this segment
                allCoordinates.append(places[i].coordinate)
                allCoordinates.append(places[i + 1].coordinate)
            }
        }

        guard allCoordinates.count >= 2 else { return }
        calculatedRoute = MKPolyline(coordinates: allCoordinates, count: allCoordinates.count)
    }

    // MARK: - Helpers

    private func regionContaining(_ places: [Place]) -> MKCoordinateRegion? {
        guard !places.isEmpty else { return nil }
        let lats = places.map { $0.latitude }
        let lngs = places.map { $0.longitude }
        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lngs.min()! + lngs.max()!) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((lats.max()! - lats.min()!) * 1.4, 0.01),
            longitudeDelta: max((lngs.max()! - lngs.min()!) * 1.4, 0.01)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}

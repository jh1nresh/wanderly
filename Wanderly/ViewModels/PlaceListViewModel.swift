import Foundation
import CoreLocation

enum PlaceFilter: String, CaseIterable {
    case all = "All"
    case wantToGo = "Want to Go"
    case visited = "Visited"
}

enum PlaceSort: String, CaseIterable {
    case recent = "Recent"
    case nearest = "Nearest"
    case rating = "Rating"
}

@MainActor
final class PlaceListViewModel: ObservableObject {
    @Published var places: [Place] = Place.mockList
    @Published var filter: PlaceFilter = .all
    @Published var sort: PlaceSort = .recent
    @Published var selectedCategories: Set<PlaceCategory> = []
    @Published var searchText: String = ""
    @Published var isLoading = false

    private let supabaseService: SupabaseServiceProtocol
    private let authService: PrivyAuthService

    init(supabaseService: SupabaseServiceProtocol = SupabaseService.shared) {
        self.supabaseService = supabaseService
        self.authService = PrivyAuthService.shared
    }

    var filteredPlaces: [Place] {
        var result = places

        // Status filter
        switch filter {
        case .all: break
        case .wantToGo: result = result.filter { $0.status == .wantToGo }
        case .visited: result = result.filter { $0.status == .visited }
        }

        // Category filter
        if !selectedCategories.isEmpty {
            result = result.filter { selectedCategories.contains($0.category) }
        }

        // Search filter
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.address.localizedCaseInsensitiveContains(searchText)
            }
        }

        // Sort
        switch sort {
        case .recent: result.sort { $0.createdAt > $1.createdAt }
        case .rating: result.sort { ($0.googleRating ?? 0) > ($1.googleRating ?? 0) }
        case .nearest: break // TODO: Sort by distance from user location
        }

        return result
    }

    func loadPlaces() async {
        guard let userId = authService.currentUserId else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            places = try await supabaseService.fetchPlaces(for: userId)
        } catch {
            print("Failed to load places: \(error)")
        }
    }

    func markVisited(_ place: Place) async {
        guard let index = places.firstIndex(where: { $0.id == place.id }) else { return }
        places[index].status = .visited
        do {
            try await supabaseService.updatePlace(places[index])
        } catch {
            print("Failed to update place: \(error)")
        }
    }

    func deletePlace(_ place: Place) async {
        places.removeAll { $0.id == place.id }
        do {
            try await supabaseService.deletePlace(place.id)
        } catch {
            print("Failed to delete place: \(error)")
        }
    }
}

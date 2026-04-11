import SwiftUI
import MapKit

struct MapView: View {
    @State private var showProfile = false
    @ObservedObject var viewModel: MapViewModel

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Map(position: $viewModel.cameraPosition) {
                    ForEach(viewModel.filteredPlaces) { place in
                        Annotation("", coordinate: place.coordinate) {
                            PlaceMapPin(place: place) {
                                viewModel.selectPlace(place)
                            }
                        }
                    }
                    if let polyline = viewModel.routePolyline {
                        MapPolyline(polyline)
                            .stroke(Color.wanderlyTerracotta, lineWidth: 3)
                    }
                }

                // Top bar: category pills + profile button
                HStack(spacing: 0) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(PlaceCategory.allCases, id: \.self) { category in
                                CategoryPill(
                                    category: category,
                                    isSelected: viewModel.selectedCategories.contains(category)
                                )
                                .onTapGesture { viewModel.toggleCategory(category) }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }

                    Button(action: { showProfile = true }) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.title2)
                            .foregroundColor(.wanderlyTerracotta)
                            .background(
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .frame(width: 36, height: 36)
                            )
                    }
                    .padding(.trailing, 16)
                }
                .background(.ultraThinMaterial)
                .padding(.top, geo.safeAreaInsets.top)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showProfile) {
            ProfileView()
        }
        .task { await viewModel.loadPlaces() }
    }
}

// MARK: - Map Pin

struct PlaceMapPin: View {
    let place: Place
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                Image(systemName: place.category.iconName)
                    .font(.caption)
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.categoryColor(for: place.category))
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)

                Image(systemName: "triangle.fill")
                    .font(.system(size: 8))
                    .foregroundColor(Color.categoryColor(for: place.category))
                    .rotationEffect(.degrees(180))
                    .offset(y: -2)
            }
        }
    }
}

import SwiftUI
import MapKit

struct PlaceDetailView: View {
    let place: Place
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Photo carousel placeholder
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.wanderlySage.opacity(0.15))
                        .frame(height: 220)

                    VStack(spacing: 8) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.largeTitle)
                            .foregroundColor(.wanderlySage)
                        Text("Photos from \(place.sourcePlatform.displayName)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)

                // Name and status
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(place.name)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.wanderlyCharcoal)
                        Text(place.address)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    CategoryPill(category: place.category, isSelected: true)
                }
                .padding(.horizontal)

                // Info grid
                VStack(spacing: 12) {
                    HStack(spacing: 16) {
                        if let rating = place.googleRating {
                            InfoChip(icon: "star.fill", text: String(format: "%.1f", rating), color: .orange)
                        }
                        if let priceRange = place.priceRange {
                            InfoChip(icon: "dollarsign.circle", text: priceRange, color: .wanderlySage)
                        }
                        InfoChip(icon: place.status == .visited ? "checkmark.circle.fill" : "clock",
                                 text: place.status.displayName,
                                 color: place.status == .visited ? .wanderlySage : .wanderlyTerracotta)
                    }

                    // Source
                    HStack {
                        PlatformIcon(platform: place.sourcePlatform)
                        Text("Saved from \(place.sourcePlatform.displayName)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        if let recommender = place.recommender {
                            Text("via \(recommender)")
                                .font(.caption)
                                .foregroundColor(.wanderlyTerracotta)
                        }

                        Spacer()
                    }
                }
                .padding(.horizontal)

                // Opening hours
                if let hours = place.openingHours {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Opening Hours", systemImage: "clock")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.wanderlyCharcoal)
                        Text(hours)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                }

                // Dishes
                if let dishes = place.extractedDishes, !dishes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Must-Try Dishes")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.wanderlyCharcoal)

                        FlowLayout(spacing: 8) {
                            ForEach(dishes, id: \.self) { dish in
                                HStack(spacing: 4) {
                                    Image(systemName: "fork.knife")
                                        .font(.caption2)
                                    Text(dish)
                                        .font(.subheadline)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.wanderlyTerracotta.opacity(0.1))
                                .foregroundColor(.wanderlyTerracotta)
                                .cornerRadius(16)
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                // Notes
                if let note = place.note {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Notes", systemImage: "note.text")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.wanderlyCharcoal)
                        Text(note)
                            .font(.subheadline)
                            .foregroundColor(.wanderlyCharcoal)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.wanderlySage.opacity(0.1))
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                }

                // Mini map
                Map(position: .constant(.region(MKCoordinateRegion(
                    center: place.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                )))) {
                    Marker(place.name, coordinate: place.coordinate)
                        .tint(Color.categoryColor(for: place.category))
                }
                .frame(height: 160)
                .cornerRadius(16)
                .padding(.horizontal)

                // Action buttons
                HStack(spacing: 12) {
                    Button(action: { openInMaps() }) {
                        Label("Navigate", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.wanderlyTerracotta)
                            .foregroundColor(.white)
                            .cornerRadius(16)
                    }

                    if let sourceUrl = place.sourceUrl, let url = URL(string: sourceUrl) {
                        Button(action: { openURL(url) }) {
                            Label("Source", systemImage: "link")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.wanderlySage.opacity(0.2))
                                .foregroundColor(.wanderlyCharcoal)
                                .cornerRadius(16)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
        }
        .background(Color.wanderlyCream)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func openInMaps() {
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: place.coordinate))
        mapItem.name = place.name
        mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }
}

// MARK: - Info Chip

struct InfoChip: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
            Text(text)
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundColor(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.12))
        .cornerRadius(12)
    }
}

#Preview {
    NavigationStack {
        PlaceDetailView(place: .mock)
    }
}

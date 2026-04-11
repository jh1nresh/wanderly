import SwiftUI
import MapKit

struct ClipContentView: View {
    @State private var tripData: SharedTripData?
    @State private var isLoading = true
    @State private var cameraPosition: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    ))

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    loadingView
                } else if let trip = tripData {
                    tripContentView(trip)
                } else {
                    errorView
                }
            }
            .background(Color(hex: "FFF8F0"))
            .navigationTitle("Trip Preview")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            handleIncomingURL(activity.webpageURL)
        }
        .onOpenURL { url in
            handleIncomingURL(url)
        }
        .task {
            // If no URL arrives after 1s, show mock data for demo
            try? await Task.sleep(for: .seconds(1))
            if tripData == nil {
                tripData = SharedTripData.demo
                updateCamera(for: SharedTripData.demo.stops)
                isLoading = false
            }
        }
    }

    // MARK: - Trip Content

    private func tripContentView(_ trip: SharedTripData) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                Map(position: $cameraPosition) {
                    ForEach(trip.stops) { stop in
                        Marker(stop.name, coordinate: stop.coordinate)
                            .tint(Color(hex: "C75B39"))
                    }
                }
                .frame(height: 200)
                .cornerRadius(16)
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 8) {
                    Text(trip.name)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(Color(hex: "2C2C2E"))

                    Text("\(trip.stops.count) stops \(trip.city.isEmpty ? "" : "in \(trip.city)")")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

                VStack(spacing: 12) {
                    ForEach(trip.stops) { stop in
                        HStack(spacing: 12) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.title3)
                                .foregroundColor(Color(hex: "C75B39"))

                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(stop.name)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(Color(hex: "2C2C2E"))
                                    Spacer()
                                    if let time = stop.time {
                                        Text(time)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                if !stop.address.isEmpty {
                                    Text(stop.address)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                if let note = stop.note {
                                    Text(note)
                                        .font(.caption)
                                        .foregroundColor(Color(hex: "C75B39").opacity(0.8))
                                }
                            }

                            Spacer()
                        }
                        .padding(12)
                        .background(Color(hex: "FFF8F0"))
                        .cornerRadius(16)
                    }
                }
                .padding(.horizontal)

                VStack(spacing: 12) {
                    Button(action: openInFullApp) {
                        Text("Open in Wanderly")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(hex: "C75B39"))
                            .cornerRadius(16)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
        }
    }

    // MARK: - Loading / Error

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .tint(Color(hex: "C75B39"))
            Text("Loading trip...")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var errorView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(Color(hex: "C75B39"))
            Text("Couldn't load this trip")
                .font(.headline)
                .foregroundColor(Color(hex: "2C2C2E"))
            Text("The link may be invalid or expired.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - URL Handling

    private func handleIncomingURL(_ url: URL?) {
        guard let url else { return }
        print("App Clip opened with URL: \(url)")

        if let data = SharedTripData.from(url: url) {
            tripData = data
            updateCamera(for: data.stops)
        }
        // Invalid URL data → tripData stays nil → errorView shown
        isLoading = false
    }

    private func updateCamera(for stops: [SharedTripData.SharedStop]) {
        let lats = stops.map(\.lat)
        let lngs = stops.map(\.lng)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLng = lngs.min(), let maxLng = lngs.max() else { return }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLng + maxLng) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.5, 0.01),
            longitudeDelta: max((maxLng - minLng) * 1.5, 0.01)
        )
        cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
    }

    private func openInFullApp() {
        guard let url = URL(string: "wanderly://trip") else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Demo Data

extension SharedTripData {
    static let demo = SharedTripData(
        name: "SF Food Tour",
        city: "San Francisco",
        stops: [
            SharedStop(id: UUID(), name: "Tartine Bakery", address: "600 Guerrero St, SF", lat: 37.7614, lng: -122.4241, time: "9:00 AM", note: "Must try the morning bun"),
            SharedStop(id: UUID(), name: "Dolores Park", address: "Dolores St, SF", lat: 37.7596, lng: -122.4269, time: "10:30 AM", note: nil),
            SharedStop(id: UUID(), name: "Bi-Rite Creamery", address: "3692 18th St, SF", lat: 37.7618, lng: -122.4256, time: "12:00 PM", note: "Salted caramel ice cream"),
        ]
    )
}

// MARK: - Hex Color (standalone for App Clip target)

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

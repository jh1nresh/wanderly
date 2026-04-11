import SwiftUI
import MapKit

struct NavigationCardComponent: View {
    let place: Place
    let mode: WanderlyAIResponse.TransportMode

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: modeIcon)
                .font(.system(size: 48))
                .foregroundColor(.wanderlyTerracotta)

            VStack(spacing: 6) {
                Text(place.name)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.wanderlyCharcoal)
                    .multilineTextAlignment(.center)

                Text(place.address)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Label(modeLabel, systemImage: modeIcon)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.wanderlyTerracotta)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.wanderlyTerracotta.opacity(0.12))
                .cornerRadius(12)

            Button(action: openInMaps) {
                Label("Start Navigation", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.wanderlyTerracotta)
                    .cornerRadius(16)
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
    }

    private var modeIcon: String {
        switch mode {
        case .walking: return "figure.walk"
        case .transit: return "tram.fill"
        case .driving: return "car.fill"
        }
    }

    private var modeLabel: String {
        switch mode {
        case .walking: return "Walking directions"
        case .transit: return "Transit directions"
        case .driving: return "Driving directions"
        }
    }

    private func openInMaps() {
        let navMode: NavigationService.Mode = switch mode {
        case .walking: .walking
        case .transit: .transit
        case .driving: .driving
        }
        NavigationService.navigate(to: place.coordinate, name: place.name, mode: navMode)
    }
}

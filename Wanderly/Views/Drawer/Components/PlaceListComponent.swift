import SwiftUI

struct PlaceListComponent: View {
    let title: String
    let places: [Place]
    let aiMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.wanderlyCharcoal)
                    if let msg = aiMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Text("\(places.count)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.wanderlyTerracotta)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            if places.isEmpty {
                Text("No matching places in your collection.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(32)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(places) { place in
                            PlaceCard(place: place)
                                .padding(.horizontal, 12)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }
}

import SwiftUI

struct TripItineraryComponent: View {
    let title: String
    let days: [ItineraryDay]
    let aiMessage: String?
    var places: [Place] = []
    @State private var showShareSheet = false

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

                Button(action: { showShareSheet = true }) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.subheadline)
                        .foregroundColor(.wanderlyTerracotta)
                }
                .sheet(isPresented: $showShareSheet) {
                    if let url = buildShareURL() {
                        ShareSheet(items: [url])
                    }
                }

                Label("\(days.count) days", systemImage: "calendar")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.wanderlyTerracotta)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(days) { day in
                        DaySection(day: day)
                    }
                }
                .padding(16)
            }
        }
    }

    private func buildShareURL() -> URL? {
        let tripData = SharedTripData.from(title: title, city: "", days: days, places: places)
        return tripData.toURL()
    }
}

// MARK: - ShareSheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Day Section

private struct DaySection: View {
    let day: ItineraryDay

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(day.label ?? "Day \(day.dayNumber)")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.wanderlyTerracotta)
                .padding(.bottom, 10)

            ForEach(Array(day.stops.enumerated()), id: \.element.id) { index, stop in
                HStack(alignment: .top, spacing: 12) {
                    // Timeline
                    VStack(spacing: 0) {
                        Circle()
                            .fill(Color.wanderlyTerracotta)
                            .frame(width: 8, height: 8)
                            .padding(.top, 5)
                        if index < day.stops.count - 1 {
                            Rectangle()
                                .fill(Color.wanderlyTerracotta.opacity(0.25))
                                .frame(width: 2)
                                .frame(maxHeight: .infinity)
                        }
                    }
                    .frame(width: 8)

                    // Content
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(stop.placeName)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.wanderlyCharcoal)
                            Spacer()
                            if let time = stop.time {
                                Text(time)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        if let duration = stop.duration {
                            Text("\(duration) min")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        if let note = stop.note {
                            Text(note)
                                .font(.caption)
                                .foregroundColor(.wanderlyTerracotta.opacity(0.8))
                                .padding(.top, 1)
                        }
                    }
                    .padding(.bottom, 14)
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.6))
        .cornerRadius(12)
    }
}

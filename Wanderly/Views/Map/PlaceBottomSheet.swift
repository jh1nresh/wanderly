import SwiftUI

struct PlaceBottomSheet: View {
    let place: Place

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(place.name)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.wanderlyCharcoal)

                    Text(place.address)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                CategoryPill(category: place.category)
            }

            Divider()

            // Info row
            HStack(spacing: 16) {
                if let rating = place.googleRating {
                    Label(String(format: "%.1f", rating), systemImage: "star.fill")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                }

                if let priceRange = place.priceRange {
                    Text(priceRange)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 4) {
                    PlatformIcon(platform: place.sourcePlatform, size: 14)
                    Text(place.sourcePlatform.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(place.status.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(place.status == .visited ? Color.wanderlySage.opacity(0.3) : Color.wanderlyTerracotta.opacity(0.15))
                    .cornerRadius(8)
            }

            // Dishes
            if let dishes = place.extractedDishes, !dishes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recommended")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)

                    FlowLayout(spacing: 6) {
                        ForEach(dishes, id: \.self) { dish in
                            Text(dish)
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.wanderlyTerracotta.opacity(0.1))
                                .cornerRadius(12)
                        }
                    }
                }
            }

            // Note
            if let note = place.note {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Note")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    Text(note)
                        .font(.subheadline)
                        .foregroundColor(.wanderlyCharcoal)
                }
            }

            // Action buttons
            HStack(spacing: 12) {
                Button(action: {
                    NavigationService.navigate(to: place.coordinate, name: place.name)
                }) {
                    Label("Navigate", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.wanderlyTerracotta)
                        .foregroundColor(.white)
                        .cornerRadius(16)
                }

                Button(action: {}) {
                    Label("Details", systemImage: "info.circle")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.wanderlySage.opacity(0.2))
                        .foregroundColor(.wanderlyCharcoal)
                        .cornerRadius(16)
                }
            }
        }
        .padding()
        .background(Color.wanderlyCream)
    }
}

// MARK: - Simple Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(subviews: subviews, proposal: proposal)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(subviews: subviews, proposal: proposal)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
        }
    }

    private func layout(subviews: Subviews, proposal: ProposedViewSize) -> (size: CGSize, frames: [CGRect]) {
        let maxWidth = proposal.width ?? .infinity
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        let totalHeight = y + rowHeight
        return (CGSize(width: maxWidth, height: totalHeight), frames)
    }
}

#Preview {
    PlaceBottomSheet(place: .mock)
}

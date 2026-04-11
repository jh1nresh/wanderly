import SwiftUI

struct OnboardingView: View {
    @State private var currentPage = 0
    var onComplete: () -> Void

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "mappin.and.ellipse",
            title: "Save Places from Anywhere",
            subtitle: "Share a link from Instagram, Threads, or any app — Wanderly's AI extracts the place details and pins it on your map.",
            color: .wanderlyTerracotta
        ),
        OnboardingPage(
            icon: "airplane",
            title: "Plan Trips Effortlessly",
            subtitle: "Group your saved spots into trips. Drag to reorder, optimize routes, and let AI schedule your perfect day.",
            color: .wanderlySage
        ),
        OnboardingPage(
            icon: "globe.americas.fill",
            title: "Track Your Adventures",
            subtitle: "Mark places as visited, build collections, and watch your world map grow with every new discovery.",
            color: .wanderlyAmber
        ),
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $currentPage) {
                ForEach(pages.indices, id: \.self) { index in
                    VStack(spacing: 32) {
                        Spacer()

                        Image(systemName: pages[index].icon)
                            .font(.system(size: 80))
                            .foregroundColor(pages[index].color)
                            .padding(.bottom, 8)

                        VStack(spacing: 12) {
                            Text(pages[index].title)
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.wanderlyCharcoal)
                                .multilineTextAlignment(.center)

                            Text(pages[index].subtitle)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }

                        Spacer()
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // Bottom controls
            VStack(spacing: 0) {
                // Page indicators
                HStack(spacing: 8) {
                    ForEach(pages.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == currentPage ? Color.wanderlyTerracotta : Color.wanderlyTerracotta.opacity(0.3))
                            .frame(width: index == currentPage ? 24 : 8, height: 8)
                            .animation(.easeInOut(duration: 0.2), value: currentPage)
                    }
                }
                .padding(.bottom, 32)

                // Button
                Button(action: {
                    if currentPage < pages.count - 1 {
                        withAnimation { currentPage += 1 }
                    } else {
                        onComplete()
                    }
                }) {
                    Text(currentPage < pages.count - 1 ? "Next" : "Get Started")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.wanderlyTerracotta)
                        .cornerRadius(16)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

                if currentPage < pages.count - 1 {
                    Button("Skip") {
                        onComplete()
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 16)
                }
            }
        }
        .background(Color.wanderlyCream)
    }
}

// MARK: - Onboarding Page Model

struct OnboardingPage {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
}

#Preview {
    OnboardingView(onComplete: {})
}

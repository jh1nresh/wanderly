import SwiftUI

struct AIDrawerView: View {
    @ObservedObject var viewModel: AIDrawerViewModel
    @Binding var drawerDetent: PresentationDetent
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            contentArea
        }
        .background(Color.wanderlyCream)
        .sheet(isPresented: $viewModel.showPlaceList) {
            PlaceListView()
        }
        .onChange(of: viewModel.drawerState) { _, state in
            withAnimation(.spring(duration: 0.3)) {
                switch state {
                case .idle:             drawerDetent = .height(72)
                case .loading:          drawerDetent = .medium
                case .error:            drawerDetent = .medium
                case .placeDetail:      drawerDetent = .medium
                case .displaying(let r):
                    drawerDetent = r.componentType == .tripItinerary ? .large : .medium
                }
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: isLoading ? "hourglass" : "sparkles")
                .foregroundColor(.wanderlyTerracotta)
                .font(.subheadline)
                .symbolEffect(.pulse, isActive: isLoading)

            TextField("Ask about your places...", text: $viewModel.query)
                .font(.subheadline)
                .foregroundColor(.wanderlyCharcoal)
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit { Task { await viewModel.submit() } }
                .onTapGesture {
                    withAnimation { drawerDetent = .medium }
                }

            if isLoading {
                ProgressView().tint(.wanderlyTerracotta).scaleEffect(0.8)
            } else if !viewModel.query.isEmpty {
                Button(action: {
                    viewModel.query = ""
                    viewModel.drawerState = .idle
                    searchFocused = true
                    withAnimation { drawerDetent = .medium }
                }) {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Content

    @ViewBuilder
    private var contentArea: some View {
        switch viewModel.drawerState {
        case .idle:
            suggestionsView

        case .loading:
            VStack(spacing: 12) {
                Spacer()
                ProgressView().tint(.wanderlyTerracotta)
                Text("Thinking...").font(.subheadline).foregroundColor(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)

        case .displaying(let response):
            ScrollView {
                VStack(spacing: 16) {
                    switch response.componentType {
                    case .placeList:
                        PlaceListComponent(
                            title: response.title ?? "Places",
                            places: viewModel.resolvePlaces(from: response.placeIds),
                            aiMessage: response.aiMessage
                        )

                    case .navigationCard:
                        if let place = viewModel.resolvePlace(id: response.navigationPlaceId) {
                            NavigationCardComponent(place: place, mode: response.transportMode)
                        } else {
                            messageView("Couldn't find that place in your collection.")
                        }

                    case .tripItinerary:
                        TripItineraryComponent(
                            title: response.title ?? "Your Itinerary",
                            days: response.itineraryDays,
                            aiMessage: response.aiMessage,
                            places: viewModel.places
                        )

                    case .message:
                        messageView(response.messageText ?? response.aiMessage ?? "")
                    }

                    // Follow-up: keeps conversation context
                    Button(action: {
                        viewModel.query = ""
                        searchFocused = true
                        withAnimation { drawerDetent = .medium }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "text.bubble")
                            Text("Follow up")
                        }
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.wanderlyTerracotta)
                        .padding(.vertical, 6)
                    }

                    // New conversation: clears context
                    Button(action: {
                        viewModel.startNewConversation()
                        searchFocused = true
                        withAnimation { drawerDetent = .medium }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.bubble")
                            Text("New question")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                    }
                }
            }

        case .placeDetail(let place):
            PlaceBottomSheet(place: place)

        case .error(let msg):
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: "exclamationmark.triangle").foregroundColor(.wanderlyTerracotta)
                Text(msg)
                    .font(.caption).foregroundColor(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal)
                Button("Try again") { Task { await viewModel.submit() } }
                    .font(.caption).fontWeight(.semibold).foregroundColor(.wanderlyTerracotta)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Idle suggestions

    private var suggestionsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                // Quick actions
                HStack(spacing: 12) {
                    Button(action: { viewModel.showPlaceList = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "list.bullet")
                            Text("My Places")
                        }
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.wanderlyTerracotta)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.wanderlyTerracotta.opacity(0.1))
                        .cornerRadius(16)
                    }

                    Text("\(viewModel.places.count) saved")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)

                // Chat history
                if !viewModel.chatHistory.isEmpty {
                    Text("Recent")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                    ForEach(viewModel.chatHistory.prefix(5)) { entry in
                        Button(action: {
                            viewModel.query = entry.query
                            Task { await viewModel.submit() }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(entry.query)
                                    .font(.subheadline)
                                    .foregroundColor(.wanderlyCharcoal)
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        }
                    }
                }

                // Suggestions
                Text("Try asking")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                ForEach(suggestions, id: \.self) { s in
                    Button(action: {
                        viewModel.query = s
                        Task { await viewModel.submit() }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up.left")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(s)
                                .font(.subheadline)
                                .foregroundColor(.wanderlyCharcoal)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                }
            }
        }
    }

    private func messageView(_ text: String) -> some View {
        VStack(spacing: 8) {
            Spacer()
            Text(text)
                .font(.subheadline)
                .foregroundColor(.wanderlyCharcoal)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var isLoading: Bool {
        if case .loading = viewModel.drawerState { return true }
        return false
    }

    private let suggestions = [
        "Show my food spots on the map",
        "Navigate to the nearest café",
        "Plan a 2-day itinerary",
        "What haven't I visited yet?",
    ]
}

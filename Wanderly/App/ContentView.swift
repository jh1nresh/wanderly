import SwiftUI

struct ContentView: View {
    @StateObject private var mapVM = MapViewModel()
    @StateObject private var drawerVM = AIDrawerViewModel()
    @State private var drawerDetent: PresentationDetent = .height(72)

    var body: some View {
        MapView(viewModel: mapVM)
            .sheet(isPresented: .constant(true)) {
                AIDrawerView(viewModel: drawerVM, drawerDetent: $drawerDetent)
                    .presentationDetents([.height(72), .medium, .large], selection: $drawerDetent)
                    .presentationDragIndicator(.visible)
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                    .interactiveDismissDisabled(true)
                    .presentationBackground(Color.wanderlyCream)
            }
            .onChange(of: drawerVM.mapAction) { _, action in
                if let action { mapVM.apply(action) }
            }
            .onChange(of: mapVM.selectedPlace) { _, place in
                if let place { drawerVM.showPlace(place) }
            }
    }
}

#Preview {
    ContentView()
}

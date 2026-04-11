import Foundation

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published var profile: UserProfile = .mock
    @Published var isLoading = false

    private let supabaseService: SupabaseServiceProtocol
    private let authService: PrivyAuthService

    init(supabaseService: SupabaseServiceProtocol = SupabaseService.shared) {
        self.supabaseService = supabaseService
        self.authService = PrivyAuthService.shared
    }

    func loadProfile() async {
        guard let userId = authService.currentUserId else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            if let profile = try await supabaseService.fetchProfile(for: userId) {
                self.profile = profile
            }
        } catch {
            print("Failed to load profile: \(error)")
        }
    }

    func signOut() async {
        await authService.signOut()
    }
}

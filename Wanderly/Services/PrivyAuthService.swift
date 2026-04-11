import SwiftUI
import AuthenticationServices
import PrivySDK

// MARK: - Auth State

enum AuthState: Equatable {
    case unknown
    case unauthenticated
    case authenticated(userId: String)
}

// MARK: - Errors

enum AuthError: LocalizedError {
    case signInFailed(String)
    case invalidCode

    var errorDescription: String? {
        switch self {
        case .signInFailed(let reason): return "Sign in failed: \(reason)"
        case .invalidCode: return "No pending email — call signInWithEmail first"
        }
    }
}

// MARK: - Privy Auth Service

@MainActor
final class PrivyAuthService: ObservableObject {
    static let shared = PrivyAuthService()

    let privy: Privy
    @Published var authState: AuthState = .unknown
    private var pendingEmail: String?

    var isAuthenticated: Bool {
        if case .authenticated = authState { return true }
        return false
    }

    var currentUserId: String? {
        if case .authenticated(let userId) = authState { return userId }
        return nil
    }

    private init() {
        let appId    = Self.keyFromPlist("PRIVY_APP_ID")     ?? ""
        let clientId = Self.keyFromPlist("PRIVY_APP_CLIENT_ID") ?? ""
        let config   = PrivyConfig(appId: appId, appClientId: clientId)
        self.privy   = PrivySdk.initialize(config: config)

        Task { await restoreSession() }
    }

    // MARK: - Session Restore

    func restoreSession() async {
        let state = await privy.getAuthState()
        applyPrivyState(state)
    }

    // MARK: - Apple

    func signInWithApple() async throws {
        let user = try await privy.oAuth.login(with: .apple)
        authState = .authenticated(userId: user.id)
    }

    // MARK: - Google

    func signInWithGoogle() async throws {
        let user = try await privy.oAuth.login(with: .google)
        authState = .authenticated(userId: user.id)
    }

    // MARK: - Email OTP

    func signInWithEmail(_ email: String) async throws {
        pendingEmail = email
        try await privy.email.sendCode(to: email)
    }

    func verifyEmailCode(_ code: String) async throws {
        guard let email = pendingEmail else { throw AuthError.invalidCode }
        let user = try await privy.email.loginWithCode(code, sentTo: email)
        pendingEmail = nil
        authState = .authenticated(userId: user.id)
    }

    // MARK: - Sign Out

    func signOut() async {
        let user = await privy.getUser()
        await user?.logout()
        authState = .unauthenticated
    }

    // MARK: - Helpers

    private func applyPrivyState(_ state: PrivySDK.AuthState) {
        switch state {
        case .authenticated(let user):
            authState = .authenticated(userId: user.id)
        case .unauthenticated:
            authState = .unauthenticated
        case .notReady, .authenticatedUnverified:
            authState = .unknown
        @unknown default:
            authState = .unknown
        }
    }

    private static func keyFromPlist(_ key: String) -> String? {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String],
              let value = dict[key],
              value != "YOUR_KEY_HERE",
              !value.isEmpty else { return nil }
        return value
    }
}

// MARK: - SignInWithApple Button (Privy-compatible)

struct SignInWithAppleButton: UIViewRepresentable {
    typealias UIViewType = ASAuthorizationAppleIDButton
    var action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(type: .continue, style: .black)
        button.addTarget(context.coordinator, action: #selector(Coordinator.tapped), for: .touchUpInside)
        return button
    }

    func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {}

    final class Coordinator: NSObject {
        let action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func tapped() { action() }
    }
}

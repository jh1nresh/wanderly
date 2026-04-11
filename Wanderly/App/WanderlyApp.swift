import SwiftUI

@main
struct WanderlyApp: App {
    @StateObject private var authService = PrivyAuthService.shared
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some Scene {
        WindowGroup {
            Group {
                if !hasCompletedOnboarding {
                    OnboardingView {
                        hasCompletedOnboarding = true
                    }
                } else {
                    switch authService.authState {
                    case .unauthenticated, .unknown:
                        SignInView()
                            .environmentObject(authService)
                    case .authenticated:
                        ContentView()
                            .environmentObject(authService)
                    }
                }
            }
            .preferredColorScheme(nil) // Respect system setting
        }
    }
}

// MARK: - Sign In View

struct SignInView: View {
    @EnvironmentObject var authService: PrivyAuthService
    @State private var email = ""
    @State private var showEmailCode = false
    @State private var verificationCode = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Logo
            VStack(spacing: 12) {
                Image(systemName: "map.fill")
                    .font(.system(size: 56))
                    .foregroundColor(.wanderlyTerracotta)

                Text("Wanderly")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.wanderlyCharcoal)

                Text("Your places, your map, your adventures")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Auth buttons
            VStack(spacing: 12) {
                SignInWithAppleButton {
                    Task {
                        isLoading = true
                        defer { isLoading = false }
                        do { try await authService.signInWithApple() }
                        catch { errorMessage = error.localizedDescription }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .cornerRadius(16)

                Button(action: {
                    Task {
                        isLoading = true
                        defer { isLoading = false }
                        do { try await authService.signInWithGoogle() }
                        catch { errorMessage = error.localizedDescription }
                    }
                }) {
                    HStack {
                        Image(systemName: "g.circle.fill")
                        Text("Continue with Google")
                    }
                    .font(.headline)
                    .foregroundColor(.wanderlyCharcoal)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white)
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                }

                // Divider
                HStack {
                    Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1)
                    Text("or").font(.caption).foregroundColor(.secondary)
                    Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1)
                }

                // Email
                if !showEmailCode {
                    HStack {
                        TextField("Email address", text: $email)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .autocapitalization(.none)

                        Button("Send Code") {
                            Task {
                                isLoading = true
                                defer { isLoading = false }
                                do {
                                    try await authService.signInWithEmail(email)
                                    showEmailCode = true
                                } catch {
                                    errorMessage = error.localizedDescription
                                }
                            }
                        }
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.wanderlyTerracotta)
                        .disabled(email.isEmpty || isLoading)
                    }
                    .padding()
                    .background(Color.white)
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.04), radius: 2)
                } else {
                    HStack {
                        TextField("Verification code", text: $verificationCode)
                            .keyboardType(.numberPad)

                        Button("Verify") {
                            Task {
                                isLoading = true
                                defer { isLoading = false }
                                do { try await authService.verifyEmailCode(verificationCode) }
                                catch { errorMessage = error.localizedDescription }
                            }
                        }
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.wanderlyTerracotta)
                        .disabled(verificationCode.isEmpty)
                    }
                    .padding()
                    .background(Color.white)
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.04), radius: 2)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)

            if isLoading {
                ProgressView()
                    .tint(.wanderlyTerracotta)
            }
        }
        .background(Color.wanderlyCream)
        .alert("Sign In Failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }
}

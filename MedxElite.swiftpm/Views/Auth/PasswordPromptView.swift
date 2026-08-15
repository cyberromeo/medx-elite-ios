import SwiftUI

public struct PasswordPromptView: View {
    public let profile: Profile
    @ObservedObject var authService = AuthService.shared
    @State private var password = ""
    @State private var localError: String?
    @FocusState private var isPasswordFocused: Bool
    @Environment(\.dismiss) private var dismiss

    public init(profile: Profile) {
        self.profile = profile
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()

                VStack(spacing: 28) {
                    // Profile Avatar
                    ZStack {
                        Circle()
                            .fill(profile.gradient)
                            .frame(width: 80, height: 80)

                        Text(String(profile.displayName.prefix(1)))
                            .font(MedxFont.rounded(36, weight: .heavy))
                            .foregroundColor(.white)
                    }
                    .shadow(color: profile.accentColor.opacity(0.4), radius: 14, x: 0, y: 6)
                    .padding(.top, 20)

                    VStack(spacing: 6) {
                        Text("Welcome, \(profile.displayName)")
                            .font(MedxFont.rounded(24, weight: .bold))

                        Text("Enter your password to unlock. It will be remembered securely on this device.")
                            .font(MedxFont.rounded(14, weight: .regular))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    // Secure Field Box
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            Image(systemName: "lock.fill")
                                .foregroundColor(profile.accentColor)

                            SecureField("Password", text: $password)
                                .focused($isPasswordFocused)
                                .submitLabel(.go)
                                .onSubmit {
                                    handleSignIn()
                                }
                        }
                        .padding(16)
                        .liquidGlassCard(cornerRadius: 18, glowColor: profile.accentColor)

                        if let err = localError ?? authService.errorMessage {
                            Text(err)
                                .font(MedxFont.rounded(13, weight: .medium))
                                .foregroundColor(MedxTheme.destructiveRed)
                                .padding(.horizontal, 8)
                        }
                    }
                    .padding(.horizontal, 24)

                    // Sign In Button
                    ModernButton(
                        title: "Sign In",
                        icon: "arrow.right",
                        gradient: profile.gradient,
                        isBusy: authService.isBusy
                    ) {
                        handleSignIn()
                    }
                    .padding(.horizontal, 24)

                    Spacer()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isPasswordFocused = true
                }
            }
        }
    }

    private func handleSignIn() {
        guard !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        localError = nil
        Task {
            do {
                try await authService.signIn(profile: profile, password: password)
                HapticManager.success()
                dismiss()
            } catch {
                HapticManager.error()
                localError = error.localizedDescription
            }
        }
    }
}

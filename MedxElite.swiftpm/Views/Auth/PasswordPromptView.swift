import SwiftUI

public struct PasswordPromptView: View {
    public let profile: Profile
    public var onCancel: (() -> Void)?

    @ObservedObject var authService = AuthService.shared
    @State private var password = ""
    @State private var isPasswordVisible = false
    @State private var localError: String?
    @FocusState private var isPasswordFocused: Bool

    public init(profile: Profile, onCancel: (() -> Void)? = nil) {
        self.profile = profile
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: 24) {
            // Profile Avatar & Welcome
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(profile.gradient)
                        .frame(width: 76, height: 76)

                    Text(String(profile.displayName.prefix(1)))
                        .font(MedxFont.rounded(32, weight: .heavy))
                        .foregroundColor(.white)
                }
                .shadow(color: profile.accentColor.opacity(0.45), radius: 16, x: 0, y: 8)

                VStack(spacing: 4) {
                    Text(profile.displayName)
                        .font(MedxFont.rounded(22, weight: .bold))
                        .foregroundColor(.white)

                    Text(profile.handle)
                        .font(MedxFont.rounded(14, weight: .medium))
                        .foregroundColor(profile.accentColor)

                    Text("Enter password to unlock. It will be saved securely.")
                        .font(MedxFont.rounded(13, weight: .regular))
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.top, 2)
                }
            }

            // Password Input Box
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: "lock.fill")
                        .foregroundColor(profile.accentColor)
                        .font(.system(size: 16, weight: .semibold))

                    if isPasswordVisible {
                        TextField("Enter password", text: $password)
                            .focused($isPasswordFocused)
                            .foregroundColor(.white)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .submitLabel(.go)
                            .onSubmit {
                                handleSignIn()
                            }
                    } else {
                        SecureField("Enter password", text: $password)
                            .focused($isPasswordFocused)
                            .foregroundColor(.white)
                            .textContentType(.password)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .submitLabel(.go)
                            .onSubmit {
                                handleSignIn()
                            }
                    }

                    // Show / Hide Password Toggle
                    Button {
                        isPasswordVisible.toggle()
                        isPasswordFocused = true
                    } label: {
                        Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                            .font(.system(size: 15))
                            .foregroundColor(.white.opacity(0.5))
                            .padding(4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            isPasswordFocused
                                ? profile.accentColor
                                : Color.white.opacity(0.15),
                            lineWidth: isPasswordFocused ? 1.5 : 1
                        )
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    isPasswordFocused = true
                }

                if let err = localError ?? authService.errorMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.caption)
                        Text(err)
                            .font(MedxFont.rounded(12, weight: .medium))
                    }
                    .foregroundColor(MedxTheme.destructiveRed)
                    .padding(.horizontal, 6)
                }
            }
            .padding(.horizontal, 24)

            // Actions
            VStack(spacing: 12) {
                // Sign In Button
                ModernButton(
                    title: "Unlock & Continue",
                    icon: "arrow.right",
                    gradient: profile.gradient,
                    isBusy: authService.isBusy
                ) {
                    handleSignIn()
                }

                // Switch Account Button
                if let cancel = onCancel {
                    Button(action: cancel) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.left")
                            Text("Choose a different profile")
                        }
                        .font(MedxFont.rounded(13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.vertical, 8)
                    }
                }
            }
            .padding(.horizontal, 24)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                isPasswordFocused = true
            }
        }
    }

    private func handleSignIn() {
        guard !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            isPasswordFocused = true
            return
        }
        localError = nil
        Task {
            do {
                try await authService.signIn(profile: profile, password: password)
                HapticManager.success()
            } catch {
                HapticManager.error()
                localError = error.localizedDescription
                isPasswordFocused = true
            }
        }
    }
}

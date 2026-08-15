import SwiftUI
import UIKit

public struct PasswordPromptView: View {
    public let profile: Profile
    public var onCancel: (() -> Void)?

    @ObservedObject var authService = AuthService.shared
    @State private var password = ""
    @State private var isPasswordVisible = false
    @State private var localError: String?
    @FocusState private var isFocused: Bool

    public init(profile: Profile, onCancel: (() -> Void)? = nil) {
        self.profile = profile
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: 28) {
            // Apple-style Glass Profile Avatar & Info
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 88, height: 88)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            profile.accentColor.opacity(0.8),
                                            Color.white.opacity(0.3)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2
                                )
                        )
                        .shadow(color: profile.accentColor.opacity(0.4), radius: 20, x: 0, y: 10)

                    Text(String(profile.displayName.prefix(1)))
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, Color.white.opacity(0.85)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }

                VStack(spacing: 6) {
                    Text(profile.displayName)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text(profile.handle)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(profile.accentColor)

                    Text("Enter password to unlock")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.white.opacity(0.55))
                        .padding(.top, 2)
                }
            }

            // Apple Liquid Glass Input Capsule
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(profile.accentColor)
                        .frame(width: 24)

                    if isPasswordVisible {
                        TextField("Password", text: $password)
                            .focused($isFocused)
                            .foregroundColor(.white)
                            .font(.system(size: 16, weight: .regular))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .submitLabel(.go)
                            .onSubmit {
                                handleSignIn()
                            }
                    } else {
                        SecureField("Password", text: $password)
                            .focused($isFocused)
                            .foregroundColor(.white)
                            .font(.system(size: 16, weight: .regular))
                            .textContentType(.password)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .submitLabel(.go)
                            .onSubmit {
                                handleSignIn()
                            }
                    }

                    // Paste Button
                    Button {
                        if let pasted = UIPasteboard.general.string {
                            password = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                            HapticManager.light()
                        }
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.65))
                            .padding(6)
                    }

                    // Show / Hide Password Toggle
                    Button {
                        isPasswordVisible.toggle()
                    } label: {
                        Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.65))
                            .padding(6)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    isFocused ? profile.accentColor : Color.white.opacity(0.35),
                                    isFocused ? profile.accentColor.opacity(0.5) : Color.white.opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: isFocused ? 1.5 : 1
                        )
                )
                .shadow(
                    color: isFocused ? profile.accentColor.opacity(0.25) : Color.black.opacity(0.2),
                    radius: 16,
                    x: 0,
                    y: 8
                )

                if let err = localError ?? authService.errorMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                        Text(err)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                    }
                    .foregroundColor(MedxTheme.destructiveRed)
                    .padding(.horizontal, 8)
                }
            }
            .padding(.horizontal, 24)

            // Apple Glass Action Buttons
            VStack(spacing: 14) {
                // Unlock Button
                Button {
                    handleSignIn()
                } label: {
                    HStack(spacing: 8) {
                        if authService.isBusy {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Unlock")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 14, weight: .bold))
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(profile.gradient)

                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.25), Color.clear],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.4), lineWidth: 1)
                    )
                    .shadow(color: profile.accentColor.opacity(0.4), radius: 18, x: 0, y: 8)
                }
                .disabled(authService.isBusy)
                .buttonStyle(GlassPressButtonStyle())

                // Switch Profile Button
                if let cancel = onCancel {
                    Button(action: cancel) {
                        HStack(spacing: 6) {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 12))
                            Text("Switch Profile")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                        }
                        .foregroundColor(.white.opacity(0.65))
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 24)
        }
        .padding(.vertical, 28)
        .liquidGlassCard(cornerRadius: 32, glowColor: profile.accentColor)
        .padding(.horizontal, 20)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isFocused = true
            }
        }
    }

    private func handleSignIn() {
        let clean = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            isFocused = true
            localError = "Please enter your password."
            return
        }
        localError = nil
        Task {
            do {
                try await authService.signIn(profile: profile, password: clean)
                HapticManager.success()
            } catch {
                HapticManager.error()
                localError = error.localizedDescription
                isFocused = true
            }
        }
    }
}

/// Pure Apple Tactile Glass Button Press Style
public struct GlassPressButtonStyle: ButtonStyle {
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

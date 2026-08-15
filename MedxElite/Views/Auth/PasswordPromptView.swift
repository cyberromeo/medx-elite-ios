import SwiftUI
import UIKit

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
        VStack(spacing: 20) {
            // Profile Avatar & Welcome
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(profile.gradient)
                        .frame(width: 70, height: 70)

                    Text(String(profile.displayName.prefix(1)))
                        .font(MedxFont.rounded(30, weight: .heavy))
                        .foregroundColor(.white)
                }
                .shadow(color: profile.accentColor.opacity(0.45), radius: 14, x: 0, y: 6)

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

                    // Paste Button
                    Button {
                        if let pasted = UIPasteboard.general.string {
                            password = pasted
                            HapticManager.light()
                        }
                    } label: {
                        Image(systemName: "doc.on.clipboard.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.6))
                            .padding(4)
                    }

                    // Show / Hide Password Toggle
                    Button {
                        isPasswordVisible.toggle()
                        isPasswordFocused = true
                    } label: {
                        Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                            .font(.system(size: 15))
                            .foregroundColor(.white.opacity(0.6))
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

            // Primary Action Buttons
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
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(.horizontal, 24)

            // On-Screen Keypad Helper (For Swift Playgrounds Preview without physical/software keyboard)
            VStack(spacing: 8) {
                HStack {
                    Text("PLAYGROUNDS KEYPAD")
                        .font(MedxFont.rounded(10, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                        .tracking(1.5)
                    Spacer()
                    Button("Clear") {
                        password = ""
                    }
                    .font(MedxFont.rounded(11, weight: .semibold))
                    .foregroundColor(MedxTheme.destructiveRed.opacity(0.8))
                }
                .padding(.horizontal, 28)

                // Quick Number Keypad grid
                let rows = [
                    ["1", "2", "3", "4", "5"],
                    ["6", "7", "8", "9", "0"],
                    ["a", "b", "c", "d", "e", "f", "g"],
                    ["h", "i", "j", "k", "l", "m", "n"],
                    ["o", "p", "q", "r", "s", "t", "u"],
                    ["v", "w", "x", "y", "z", "@", ".", "!"]
                ]

                VStack(spacing: 5) {
                    ForEach(rows, id: \.self) { row in
                        HStack(spacing: 5) {
                            ForEach(row, id: \.self) { char in
                                Button {
                                    HapticManager.light()
                                    password.append(char)
                                } label: {
                                    Text(char)
                                        .font(MedxFont.monospacedDigits(14, weight: .semibold))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 32)
                                        .background(Color.white.opacity(0.1))
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                            }

                            if row == rows.last {
                                Button {
                                    HapticManager.light()
                                    if !password.isEmpty {
                                        password.removeLast()
                                    }
                                } label: {
                                    Image(systemName: "delete.left.fill")
                                        .font(.system(size: 13))
                                        .foregroundColor(.white.opacity(0.8))
                                        .frame(width: 44, height: 32)
                                        .background(Color.white.opacity(0.15))
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.top, 8)
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

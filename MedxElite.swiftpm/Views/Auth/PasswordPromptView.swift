import SwiftUI

public struct PasswordPromptView: View {
    public let profile: Profile
    @ObservedObject var authService = AuthService.shared
    @State private var password = ""
    @State private var localError: String?
    @State private var hasAppeared = false
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) private var dismiss

    public init(profile: Profile) {
        self.profile = profile
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // MARK: - Profile Header
                VStack(spacing: 16) {
                    // Avatar with glow
                    ZStack {
                        Circle()
                            .fill(profile.gradient)
                            .frame(width: 88, height: 88)
                            .blur(radius: 30)
                            .opacity(0.4)

                        Circle()
                            .fill(profile.gradient)
                            .frame(width: 80, height: 80)

                        Text(String(profile.displayName.prefix(1)))
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    .scaleEffect(hasAppeared ? 1 : 0.8)
                    .opacity(hasAppeared ? 1 : 0)

                    VStack(spacing: 4) {
                        Text(profile.displayName)
                            .font(MedxFont.titleRounded(22))

                        Text(profile.email)
                            .font(MedxFont.caption(13))
                            .foregroundColor(.secondary)
                    }
                    .opacity(hasAppeared ? 1 : 0)
                    .offset(y: hasAppeared ? 0 : 8)
                }
                .padding(.top, 40)
                .padding(.bottom, 36)

                // MARK: - Password Field
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Password")
                            .font(MedxFont.label(13))
                            .foregroundColor(.secondary)

                        SecureField("Enter your password", text: $password)
                            .focused($isFocused)
                            .textContentType(.password)
                            .submitLabel(.go)
                            .onSubmit { handleSignIn() }
                            .font(MedxFont.body(16))
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color(uiColor: .tertiarySystemGroupedBackground))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(
                                        isFocused ? profile.accentColor.opacity(0.5) : Color.clear,
                                        lineWidth: 1.5
                                    )
                            )
                            .animation(.easeInOut(duration: 0.2), value: isFocused)
                    }
                    .padding(.horizontal, 28)
                    .opacity(hasAppeared ? 1 : 0)
                    .offset(y: hasAppeared ? 0 : 12)

                    // Error
                    if let err = localError ?? authService.errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.system(size: 13))
                            Text(err)
                                .font(MedxFont.caption(13))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 28)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }

                Spacer()

                // MARK: - Sign In Button
                VStack(spacing: 12) {
                    Button(action: handleSignIn) {
                        HStack(spacing: 10) {
                            if authService.isBusy {
                                ProgressView()
                                    .tint(.white)
                                    .controlSize(.small)
                                Text("Signing In…")
                                    .font(MedxFont.headline(16))
                            } else {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 14, weight: .bold))
                                Text("Sign In")
                                    .font(MedxFont.headline(16))
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            password.isEmpty ? AnyShapeStyle(Color.secondary.opacity(0.3)) : AnyShapeStyle(profile.gradient)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(
                            color: password.isEmpty ? .clear : profile.accentColor.opacity(0.3),
                            radius: 12,
                            y: 6
                        )
                    }
                    .disabled(password.isEmpty || authService.isBusy)
                    .buttonStyle(BouncyButtonStyle())
                    .padding(.horizontal, 28)
                    .opacity(hasAppeared ? 1 : 0)
                    .offset(y: hasAppeared ? 0 : 16)

                    // Face ID hint
                    if authService.hasSavedPassword(for: profile.id) {
                        Label("Password saved in Keychain", systemImage: "key.fill")
                            .font(MedxFont.caption(12))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.bottom, 32)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(MedxFont.body(16))
                }
            }
            .onAppear {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.85).delay(0.1)) {
                    hasAppeared = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    isFocused = true
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
    }

    private func handleSignIn() {
        let clean = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        localError = nil
        Task {
            do {
                try await authService.signIn(profile: profile, password: clean)
                dismiss()
            } catch {
                localError = error.localizedDescription
            }
        }
    }
}

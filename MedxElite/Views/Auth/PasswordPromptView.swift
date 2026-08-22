import SwiftUI

/// Password entry for one profile. Sheet-sized, keyboard-first.
public struct PasswordPromptView: View {
    public let profile: Profile

    @ObservedObject private var authService = AuthService.shared
    @State private var password = ""
    @State private var localError: String?
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) private var dismiss

    public init(profile: Profile) {
        self.profile = profile
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header

                VStack(alignment: .leading, spacing: 8) {
                    SecureField("Password", text: $password)
                        .focused($isFocused)
                        .textContentType(.password)
                        .submitLabel(.go)
                        .onSubmit(handleSignIn)
                        .font(.body)
                        .padding(14)
                        .background(MedxSurface.cardFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(
                                    isFocused ? Color.accentColor.opacity(0.55) : MedxSurface.separator.opacity(0.35),
                                    lineWidth: isFocused ? 1.5 : MedxSurface.hairline
                                )
                        )
                        .animation(.easeInOut(duration: 0.18), value: isFocused)

                    if let error = localError ?? authService.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(MedxTheme.destructiveRed)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 24)

                Spacer(minLength: 20)

                VStack(spacing: 10) {
                    Button(action: handleSignIn) {
                        HStack(spacing: 8) {
                            if authService.isBusy {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Signing in…")
                            } else {
                                Text("Sign In")
                            }
                        }
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .disabled(password.isEmpty || authService.isBusy)

                    if authService.hasSavedPassword(for: profile.id) {
                        Label("Password saved in the Keychain", systemImage: "key.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
            .background(MedxSurface.groupedBackground.ignoresSafeArea())
            .navigationTitle("Sign In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                // A short delay so the sheet finishes presenting before the keyboard rises.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    isFocused = true
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        VStack(spacing: 12) {
            ProfileAvatarView(profile: profile, size: 72)

            VStack(spacing: 3) {
                Text(profile.displayName)
                    .font(.title3.weight(.semibold))
                Text(profile.email)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 28)
        .padding(.bottom, 28)
        .accessibilityElement(children: .combine)
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
                HapticManager.error()
            }
        }
    }
}

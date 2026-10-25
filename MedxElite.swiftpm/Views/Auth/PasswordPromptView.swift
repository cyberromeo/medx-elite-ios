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
            List {
                Section {
                    VStack(spacing: MedxSpace.m) {
                        ProfileAvatarView(profile: profile, size: 72)

                        VStack(spacing: 2) {
                            Text(profile.displayName)
                                .font(.title3.weight(.semibold))
                            Text(profile.email)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, MedxSpace.l)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .accessibilityElement(children: .combine)
                }

                Section {
                    SecureField("Password", text: $password)
                        .focused($isFocused)
                        .textContentType(.password)
                        .submitLabel(.go)
                        .onSubmit(handleSignIn)
                } footer: {
                    if let error = localError ?? authService.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(MedxOutcome.wrong)
                    } else if authService.hasSavedPassword(for: profile.id) {
                        Label("A password is saved in the Keychain for this profile.", systemImage: "key.fill")
                    }
                }

                Section {
                    Button(action: handleSignIn) {
                        HStack(spacing: MedxSpace.s) {
                            if authService.isBusy {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Signing in…")
                            } else {
                                Text("Sign in")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .medxPrimary()
                    .disabled(password.isEmpty || authService.isBusy)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Sign in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                // A short delay so the sheet finishes presenting before the keyboard rises.
                // `Task` rather than `DispatchQueue.asyncAfter`, whose block is `@Sendable`
                // and so cannot touch `@FocusState`.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    isFocused = true
                }
            }
        }
        .medxTaskSheet()
    }

    private func handleSignIn() {
        // Sent as typed: a password with a leading or trailing space could never sign in.
        let clean = password
        guard !clean.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
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

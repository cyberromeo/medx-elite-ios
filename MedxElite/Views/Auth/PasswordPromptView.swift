import SwiftUI

public struct PasswordPromptView: View {
    public let profile: Profile
    @ObservedObject var authService = AuthService.shared
    @State private var password = ""
    @State private var localError: String?
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) private var dismiss

    public init(profile: Profile) {
        self.profile = profile
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(profile.gradient)
                                    .frame(width: 64, height: 64)

                                Text(String(profile.displayName.prefix(1)))
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                            }

                            Text(profile.displayName)
                                .font(.title2.bold())

                            Text(profile.email)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                Section("Password") {
                    SecureField("Enter your password", text: $password)
                        .focused($isFocused)
                        .textContentType(.password)
                        .submitLabel(.go)
                        .onSubmit {
                            handleSignIn()
                        }
                }

                if let err = localError ?? authService.errorMessage {
                    Section {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.footnote)
                    }
                }

                Section {
                    Button(action: handleSignIn) {
                        HStack {
                            Spacer()
                            if authService.isBusy {
                                ProgressView()
                                    .padding(.trailing, 8)
                                Text("Signing In…")
                            } else {
                                Text("Sign In")
                            }
                            Spacer()
                        }
                    }
                    .disabled(password.isEmpty || authService.isBusy)
                }
            }
            .navigationTitle("Sign In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isFocused = true
                }
            }
        }
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

import SwiftUI

public struct ProfileSelectView: View {
    @ObservedObject var authService = AuthService.shared
    @State private var selectedProfile: Profile?
    @State private var showPasswordPrompt = false

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Profile.allProfiles) { profile in
                        Button {
                            handleProfileTap(profile)
                        } label: {
                            HStack(spacing: 14) {
                                // SF Symbol Avatar
                                ZStack {
                                    Circle()
                                        .fill(profile.gradient)
                                        .frame(width: 48, height: 48)

                                    Text(String(profile.displayName.prefix(1)))
                                        .font(.system(size: 20, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(profile.displayName)
                                        .font(.headline)
                                        .foregroundColor(.primary)

                                    Text(profile.handle)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                if authService.isBusy && selectedProfile?.id == profile.id {
                                    ProgressView()
                                } else if authService.hasSavedPassword(for: profile.id) {
                                    Image(systemName: "checkmark.seal.fill")
                                        .foregroundColor(.green)
                                        .font(.body)
                                } else {
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: {
                    Text("Choose Profile")
                } footer: {
                    Text("Passwords are stored securely in the iOS Keychain.")
                }

                if let err = authService.errorMessage {
                    Section {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Medx-elite")
            .sheet(item: $selectedProfile) { profile in
                PasswordPromptView(profile: profile)
            }
        }
    }

    private func handleProfileTap(_ profile: Profile) {
        if authService.hasSavedPassword(for: profile.id) {
            selectedProfile = profile
            Task {
                do {
                    try await authService.signIn(profile: profile, password: nil)
                } catch {
                    selectedProfile = profile
                }
            }
        } else {
            selectedProfile = profile
        }
    }
}

import SwiftUI

/// Profile chooser. Two known accounts, a saved-password fast path, and nothing else.
public struct ProfileSelectView: View {
    @ObservedObject private var authService = AuthService.shared
    /// Observed so the sign-in screen repaints when the accent changes — it lives outside
    /// `MainTabView`, which is where the rest of the app picks the change up.
    @ObservedObject private var medxTheme = MedxAccentThemeStore.shared
    @State private var selectedProfile: Profile?

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: MedxSpace.m) {
                        MedxLogoMark(size: 78)

                        Text("MedX Elite")
                            .font(.largeTitle.weight(.bold))

                        Text("Choose your profile to continue")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, MedxSpace.xl)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .accessibilityElement(children: .combine)
                }

                Section {
                    ForEach(Profile.allProfiles) { profile in
                        profileRow(profile)
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: MedxSpace.s) {
                        if let error = authService.errorMessage {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(MedxOutcome.wrong)
                        }
                        Label("Passwords stay in the iOS Keychain.", systemImage: "lock.shield")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .sheet(item: $selectedProfile) { profile in
                PasswordPromptView(profile: profile)
            }
        }
    }

    private func profileRow(_ profile: Profile) -> some View {
        Button {
            handleProfileTap(profile)
        } label: {
            HStack(spacing: MedxSpace.m) {
                ProfileAvatarView(profile: profile, size: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.displayName)
                        .foregroundStyle(.primary)
                    Text("@\(profile.handle) · \(profile.duelTag)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: MedxSpace.s)

                if authService.isBusy, selectedProfile?.id == profile.id {
                    ProgressView()
                        .controlSize(.small)
                } else if authService.hasSavedPassword(for: profile.id) {
                    Image(systemName: "faceid")
                        .foregroundStyle(MedxOutcome.correct)
                        .accessibilityLabel("Password saved")
                } else {
                    MedxRowChevron()
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sign in as \(profile.displayName)")
    }

    private func handleProfileTap(_ profile: Profile) {
        HapticManager.light()
        selectedProfile = profile

        // With a saved password the sheet is a formality — try the silent sign-in first and
        // let the sheet be the fallback if it fails.
        guard authService.hasSavedPassword(for: profile.id) else { return }
        Task {
            try? await authService.signIn(profile: profile, password: nil)
        }
    }
}

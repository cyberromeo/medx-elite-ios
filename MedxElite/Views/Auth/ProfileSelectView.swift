import SwiftUI

/// Profile chooser. Two known accounts, a saved-password fast path, and nothing else.
public struct ProfileSelectView: View {
    @ObservedObject private var authService = AuthService.shared
    @State private var selectedProfile: Profile?

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer(minLength: 24)

                branding

                VStack(spacing: 12) {
                    ForEach(Profile.allProfiles) { profile in
                        profileCard(profile)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 32)

                if let error = authService.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 18)
                        .transition(.opacity)
                }

                Spacer(minLength: 24)

                Label("Credentials stored in the iOS Keychain", systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity)
            .background(MedxSurface.groupedBackground.ignoresSafeArea())
            .sheet(item: $selectedProfile) { profile in
                PasswordPromptView(profile: profile)
            }
        }
    }

    private var branding: some View {
        VStack(spacing: 10) {
            Image(systemName: "heart.text.clipboard.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 78, height: 78)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            Text("MedX Elite")
                .font(.largeTitle.weight(.bold))

            Text("Choose your profile to continue")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func profileCard(_ profile: Profile) -> some View {
        Button {
            handleProfileTap(profile)
        } label: {
            HStack(spacing: 14) {
                ProfileAvatarView(profile: profile, size: 52)

                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("@\(profile.handle)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if authService.isBusy, selectedProfile?.id == profile.id {
                    ProgressView()
                        .controlSize(.small)
                } else if authService.hasSavedPassword(for: profile.id) {
                    Image(systemName: "faceid")
                        .font(.title3)
                        .foregroundStyle(MedxTheme.successGreen)
                        .accessibilityLabel("Password saved")
                } else {
                    MedxDisclosure()
                }
            }
            .padding(16)
            .frame(minHeight: 76)
            .medxCard()
            .contentShape(RoundedRectangle(cornerRadius: MedxSurface.cardRadius, style: .continuous))
        }
        .buttonStyle(BouncyButtonStyle())
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

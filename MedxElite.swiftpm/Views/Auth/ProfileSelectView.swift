import SwiftUI

public struct ProfileSelectView: View {
    @ObservedObject var authService = AuthService.shared
    @State private var selectedProfile: Profile?
    @State private var showPasswordPrompt = false
    @State private var hasAppeared = false

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer()

                    // App branding
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.accentColor.opacity(0.12))
                                .frame(width: 84, height: 84)
                                .overlay(Circle().strokeBorder(Color.accentColor.opacity(0.24), lineWidth: 1))

                            Image(systemName: "heart.text.clipboard.fill")
                                .font(.system(size: 36, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                        .opacity(hasAppeared ? 1 : 0)
                        .scaleEffect(hasAppeared ? 1 : 0.8)

                        Text("MedX Elite")
                            .font(.largeTitle.weight(.bold))
                            .foregroundColor(.primary)
                            .opacity(hasAppeared ? 1 : 0)
                            .offset(y: hasAppeared ? 0 : 10)

                        Text("Choose your profile to continue")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .opacity(hasAppeared ? 1 : 0)
                            .offset(y: hasAppeared ? 0 : 10)
                    }
                    .padding(.bottom, 36)

                    // Profile Cards
                    VStack(spacing: 16) {
                        ForEach(Array(Profile.allProfiles.enumerated()), id: \.element.id) { index, profile in
                            profileCard(profile, delay: Double(index) * 0.1)
                        }
                    }
                    .padding(.horizontal, 28)

                    // Error message
                    if let err = authService.errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.system(size: 14))
                            Text(err)
                                .font(MedxFont.caption(13))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 28)
                        .padding(.top, 16)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    Spacer()

                    // Footer
                    HStack(spacing: 6) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 11))
                        Text("Credentials secured with iOS Keychain")
                            .font(MedxFont.caption(12))
                    }
                    .foregroundColor(Color(uiColor: .tertiaryLabel))
                    .padding(.bottom, 20)
                }
            }
            .sheet(item: $selectedProfile) { profile in
                PasswordPromptView(profile: profile)
            }
            .onAppear {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.8).delay(0.1)) {
                    hasAppeared = true
                }
            }
        }
    }

    // MARK: - Profile Card

    private func profileCard(_ profile: Profile, delay: Double) -> some View {
        Button {
            handleProfileTap(profile)
        } label: {
            HStack(spacing: 16) {
                // Avatar with gradient ring
                ZStack {
                    Circle()
                        .fill(profile.accentColor.opacity(0.14))
                        .frame(width: 56, height: 56)
                        .overlay(Circle().strokeBorder(profile.accentColor.opacity(0.36), lineWidth: 1))

                    Text(String(profile.displayName.prefix(1)).uppercased())
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(profile.accentColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.displayName)
                        .font(MedxFont.headline(18))
                        .foregroundColor(.primary)

                    Text("@\(profile.handle)")
                        .font(MedxFont.caption(14))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Status indicator
                if authService.isBusy && selectedProfile?.id == profile.id {
                    ProgressView()
                        .tint(profile.accentColor)
                } else if authService.hasSavedPassword(for: profile.id) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(MedxTheme.successGreen)
                        .symbolEffect(.pulse, options: .repeating.speed(0.5))
                } else {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(Color(uiColor: .tertiaryLabel))
                }
            }
            .padding(18)
            .frame(minHeight: 76)
            .liquidGlassCard(cornerRadius: 18)
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Choose profile \(profile.displayName)")
        .accessibilityHint("Opens this profile")
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 20)
        .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.2 + delay), value: hasAppeared)
    }

    // MARK: - Background

    private var meshBackground: some View {
        Color(uiColor: .systemBackground)
            .ignoresSafeArea()
    }

    // MARK: - Actions

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

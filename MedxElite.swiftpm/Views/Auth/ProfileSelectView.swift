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
                // Mesh-style gradient background
                meshBackground
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer()

                    // App branding
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(MedxTheme.auroraGradient)
                                .frame(width: 80, height: 80)
                                .blur(radius: 20)
                                .opacity(0.5)

                            Image(systemName: "heart.text.clipboard.fill")
                                .font(.system(size: 36, weight: .semibold))
                                .foregroundStyle(MedxTheme.auroraGradient)
                                .symbolEffect(.pulse.byLayer, options: .repeating.speed(0.3))
                        }
                        .opacity(hasAppeared ? 1 : 0)
                        .scaleEffect(hasAppeared ? 1 : 0.8)

                        Text("MedX Elite")
                            .font(MedxFont.hero(28))
                            .foregroundColor(.primary)
                            .opacity(hasAppeared ? 1 : 0)
                            .offset(y: hasAppeared ? 0 : 10)

                        Text("Choose your profile to continue")
                            .font(MedxFont.body(15))
                            .foregroundColor(.secondary)
                            .opacity(hasAppeared ? 1 : 0)
                            .offset(y: hasAppeared ? 0 : 10)
                    }
                    .padding(.bottom, 40)

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
                    Text("Passwords are stored securely in the iOS Keychain")
                        .font(MedxFont.caption(11))
                        .foregroundColor(.quaternaryLabel)
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
                        .strokeBorder(profile.gradient, lineWidth: 2.5)
                        .frame(width: 56, height: 56)

                    Circle()
                        .fill(profile.gradient)
                        .frame(width: 48, height: 48)

                    Text(String(profile.displayName.prefix(1)))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
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
                        .foregroundColor(.secondary.opacity(0.4))
                }
            }
            .padding(18)
            .glassCard(cornerRadius: 22, shadowLevel: 2)
        }
        .buttonStyle(BouncyButtonStyle())
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 20)
        .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.2 + delay), value: hasAppeared)
    }

    // MARK: - Background

    private var meshBackground: some View {
        ZStack {
            Color(uiColor: .systemBackground)

            // Top-left glow
            Circle()
                .fill(MedxTheme.primaryBlue.opacity(0.08))
                .frame(width: 300, height: 300)
                .blur(radius: 80)
                .offset(x: -100, y: -200)

            // Bottom-right glow
            Circle()
                .fill(MedxTheme.primaryPurple.opacity(0.06))
                .frame(width: 400, height: 400)
                .blur(radius: 100)
                .offset(x: 120, y: 300)

            // Center-right accent
            Circle()
                .fill(MedxTheme.primaryPink.opacity(0.04))
                .frame(width: 250, height: 250)
                .blur(radius: 60)
                .offset(x: 80, y: 50)
        }
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

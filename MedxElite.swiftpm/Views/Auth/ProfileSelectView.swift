import SwiftUI

public struct ProfileSelectView: View {
    @ObservedObject var authService = AuthService.shared
    @State private var selectedProfile: Profile?

    public init() {}

    public var body: some View {
        ZStack {
            // Living Ambient Apple Mesh Aura
            AmbientGlassAuraBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 36) {
                    Spacer(minLength: 50)

                    // Apple-style Monogram App Header
                    VStack(spacing: 12) {
                        // Glass Icon Badge
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 64, height: 64)
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.white.opacity(0.35), lineWidth: 1.5)
                                )
                                .shadow(color: MedxTheme.cyanAccent.opacity(0.3), radius: 18, x: 0, y: 8)

                            Image(systemName: "cross.case.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [MedxTheme.cyanAccent, MedxTheme.primaryPink],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }

                        VStack(spacing: 4) {
                            Text("MEDX-ELITE")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .tracking(3.0)
                                .foregroundColor(MedxTheme.cyanAccent)

                            Text("FMGE 2027 Suite")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundColor(.white)

                            Text("Select your profile to continue")
                                .font(.system(size: 15, weight: .regular))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }

                    if let profile = selectedProfile {
                        // Apple-style Frosted Password Modal Card
                        PasswordPromptView(profile: profile) {
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                                selectedProfile = nil
                            }
                        }
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.94)),
                            removal: .opacity.combined(with: .scale(scale: 0.94))
                        ))
                    } else {
                        // Apple Glass Profile Selection Cards
                        VStack(spacing: 16) {
                            ForEach(Profile.allProfiles) { profile in
                                ProfileGlassCard(
                                    profile: profile,
                                    hasSavedPassword: authService.hasSavedPassword(for: profile.id),
                                    isBusy: authService.isBusy && selectedProfile?.id == profile.id
                                ) {
                                    handleProfileTap(profile)
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.94)),
                            removal: .opacity.combined(with: .scale(scale: 0.94))
                        ))
                    }

                    if let err = authService.errorMessage, selectedProfile == nil {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.circle.fill")
                            Text(err)
                        }
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(MedxTheme.destructiveRed)
                        .padding(.horizontal, 24)
                    }

                    Spacer(minLength: 50)

                    // Apple Encrypted Privacy Badge
                    HStack(spacing: 6) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 11))
                        Text("Encrypted On-Device Keychain Session")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                    }
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.bottom, 20)
                }
                .frame(minHeight: UIScreen.main.bounds.height - 60)
            }
        }
    }

    private func handleProfileTap(_ profile: Profile) {
        HapticManager.medium()
        if authService.hasSavedPassword(for: profile.id) {
            Task {
                do {
                    try await authService.signIn(profile: profile, password: nil)
                    HapticManager.success()
                } catch {
                    HapticManager.error()
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                        selectedProfile = profile
                    }
                }
            }
        } else {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                selectedProfile = profile
            }
        }
    }
}

/// Pure Apple Liquid Glass Profile Card
private struct ProfileGlassCard: View {
    let profile: Profile
    let hasSavedPassword: Bool
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Glass Monogram Avatar
                ZStack {
                    Circle()
                        .fill(profile.gradient)
                        .frame(width: 54, height: 54)

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.35), Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 54, height: 54)

                    Text(String(profile.displayName.prefix(1)))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.4), lineWidth: 1.5)
                )
                .shadow(color: profile.accentColor.opacity(0.4), radius: 12, x: 0, y: 6)

                // Info
                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.displayName)
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text(profile.handle)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(profile.accentColor)
                }

                Spacer()

                // Trailing Status Indicator
                if isBusy {
                    ProgressView()
                        .tint(.white)
                } else if hasSavedPassword {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 13))
                        Text("Unlocked")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(MedxTheme.successGreen)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(MedxTheme.successGreen.opacity(0.4), lineWidth: 1)
                    )
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .liquidGlassCard(cornerRadius: 24, glowColor: profile.accentColor)
        }
        .buttonStyle(GlassPressButtonStyle())
    }
}

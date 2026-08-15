import SwiftUI

public struct ProfileSelectView: View {
    @ObservedObject var authService = AuthService.shared
    @State private var selectedProfile: Profile?
    @State private var animateGlow = false

    public init() {}

    public var body: some View {
        ZStack {
            // Dynamic Aura Background
            Color.black.ignoresSafeArea()

            // Ambient Glow orbs
            ZStack {
                Circle()
                    .fill(Color(hex: "#0A84FF").opacity(0.35))
                    .frame(width: 320, height: 320)
                    .blur(radius: 80)
                    .offset(x: animateGlow ? -60 : 60, y: animateGlow ? -120 : -60)

                Circle()
                    .fill(Color(hex: "#FF375F").opacity(0.3))
                    .frame(width: 300, height: 300)
                    .blur(radius: 80)
                    .offset(x: animateGlow ? 80 : -40, y: animateGlow ? 160 : 80)

                Circle()
                    .fill(Color(hex: "#BF5AF2").opacity(0.25))
                    .frame(width: 280, height: 280)
                    .blur(radius: 70)
                    .offset(x: animateGlow ? -100 : 100, y: animateGlow ? 80 : -100)
            }
            .animation(.easeInOut(duration: 8).repeatForever(autoreverses: true), value: animateGlow)
            .onAppear { animateGlow = true }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 32) {
                    Spacer(minLength: 40)

                    // Header Title
                    VStack(spacing: 10) {
                        Text("FMGE · JANUARY 2027")
                            .font(MedxFont.rounded(12, weight: .bold))
                            .foregroundColor(MedxTheme.cyanAccent)
                            .tracking(2.5)

                        HStack(spacing: 0) {
                            Text("Medx")
                                .font(MedxFont.rounded(42, weight: .black))
                                .foregroundColor(.white)
                            Text("-elite")
                                .font(MedxFont.rounded(42, weight: .light))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [MedxTheme.cyanAccent, MedxTheme.primaryPink],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        }

                        Text("Private high-yield study suite for FMGE")
                            .font(MedxFont.rounded(15, weight: .regular))
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }

                    if let profile = selectedProfile {
                        // Inline Password Entry Card (Guarantees immediate keyboard focus on iPad Playgrounds)
                        PasswordPromptView(profile: profile) {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                selectedProfile = nil
                            }
                        }
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.94)),
                            removal: .opacity.combined(with: .scale(scale: 0.94))
                        ))
                    } else {
                        // Profile Picker Cards
                        VStack(spacing: 18) {
                            ForEach(Profile.allProfiles) { profile in
                                ProfileCardButton(
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
                        Text(err)
                            .font(MedxFont.rounded(14, weight: .medium))
                            .foregroundColor(MedxTheme.destructiveRed)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    Spacer(minLength: 40)

                    // Footer
                    Text("Exclusive 2-Member Environment")
                        .font(MedxFont.rounded(12, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.bottom, 16)
                }
                .frame(minHeight: UIScreen.main.bounds.height - 80)
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
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        selectedProfile = profile
                    }
                }
            }
        } else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                selectedProfile = profile
            }
        }
    }
}

private struct ProfileCardButton: View {
    let profile: Profile
    let hasSavedPassword: Bool
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Profile Avatar Circle
                ZStack {
                    Circle()
                        .fill(profile.gradient)
                        .frame(width: 58, height: 58)

                    Text(String(profile.displayName.prefix(1)))
                        .font(MedxFont.rounded(24, weight: .bold))
                        .foregroundColor(.white)
                }
                .shadow(color: profile.accentColor.opacity(0.4), radius: 10, x: 0, y: 4)

                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.handle)
                        .font(MedxFont.rounded(19, weight: .bold))
                        .foregroundColor(.white)

                    Text(profile.displayName)
                        .font(MedxFont.rounded(14, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }

                Spacer()

                if isBusy {
                    ProgressView()
                        .tint(.white)
                } else if hasSavedPassword {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(MedxTheme.successGreen)
                        Text("Saved")
                            .font(MedxFont.rounded(13, weight: .bold))
                            .foregroundColor(MedxTheme.successGreen)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(MedxTheme.successGreen.opacity(0.15))
                    .clipShape(Capsule())
                } else {
                    Image(systemName: "chevron.right")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                profile.accentColor.opacity(0.6),
                                Color.white.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            )
            .shadow(color: profile.accentColor.opacity(0.2), radius: 16, x: 0, y: 8)
        }
        .buttonStyle(BouncyButtonStyle())
    }
}

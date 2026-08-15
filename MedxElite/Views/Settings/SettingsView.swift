import SwiftUI

public struct SettingsView: View {
    @ObservedObject var authService = AuthService.shared
    @State private var showSignOutConfirm = false
    @State private var showForgetCachedConfirm = false
    @State private var cacheCleared = false
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Current Profile Header Card
                        if let profile = authService.currentProfile {
                            VStack(spacing: 14) {
                                ZStack {
                                    Circle()
                                        .fill(profile.gradient)
                                        .frame(width: 72, height: 72)
                                    Text(String(profile.displayName.prefix(1)))
                                        .font(MedxFont.rounded(32, weight: .bold))
                                        .foregroundColor(.white)
                                }
                                .shadow(color: profile.accentColor.opacity(0.4), radius: 10, x: 0, y: 4)

                                VStack(spacing: 4) {
                                    Text(profile.displayName)
                                        .font(MedxFont.rounded(20, weight: .bold))
                                    Text("@\(profile.handle)")
                                        .font(MedxFont.rounded(14, weight: .medium))
                                        .foregroundColor(.secondary)
                                    Text(profile.email)
                                        .font(MedxFont.rounded(13, weight: .regular))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(24)
                            .liquidGlassCard(cornerRadius: 24, glowColor: profile.accentColor)
                            .padding(.horizontal, 20)
                            .padding(.top, 10)
                        }

                        // Actions Section
                        VStack(spacing: 12) {
                            // Clear Offline Cache Button
                            Button {
                                Task {
                                    await CacheManager.shared.clearAll()
                                    HapticManager.success()
                                    withAnimation {
                                        cacheCleared = true
                                    }
                                }
                            } label: {
                                HStack {
                                    Label("Clear Offline Cache", systemImage: "trash")
                                        .font(MedxFont.rounded(15, weight: .medium))
                                        .foregroundColor(.primary)
                                    Spacer()
                                    if cacheCleared {
                                        Text("Cleared")
                                            .font(MedxFont.rounded(13, weight: .bold))
                                            .foregroundColor(MedxTheme.successGreen)
                                    }
                                }
                                .padding(16)
                                .liquidGlassCard(cornerRadius: 16)
                            }
                            .buttonStyle(PlainButtonStyle())

                            // Switch / Sign Out Button
                            Button {
                                showSignOutConfirm = true
                            } label: {
                                HStack {
                                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                                        .font(MedxFont.rounded(15, weight: .medium))
                                        .foregroundColor(MedxTheme.warningOrange)
                                    Spacer()
                                }
                                .padding(16)
                                .liquidGlassCard(cornerRadius: 16)
                            }
                            .buttonStyle(PlainButtonStyle())

                            // Sign Out & Forget Saved Password
                            if let profile = authService.currentProfile, authService.hasSavedPassword(for: profile.id) {
                                Button {
                                    showForgetCachedConfirm = true
                                } label: {
                                    HStack {
                                        Label("Sign Out & Forget Saved Password", systemImage: "key.slash")
                                            .font(MedxFont.rounded(15, weight: .medium))
                                            .foregroundColor(MedxTheme.destructiveRed)
                                        Spacer()
                                    }
                                    .padding(16)
                                    .liquidGlassCard(cornerRadius: 16)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal, 20)

                        // App Info
                        VStack(spacing: 4) {
                            Text("Medx-elite for iOS")
                                .font(MedxFont.rounded(13, weight: .bold))
                                .foregroundColor(.secondary)
                            Text("Version 1.0.0 · Swift Native")
                                .font(MedxFont.rounded(12, weight: .regular))
                                .foregroundColor(.secondary.opacity(0.8))
                        }
                        .padding(.top, 16)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .confirmationDialog("Sign Out?", isPresented: $showSignOutConfirm) {
                Button("Sign Out", role: .destructive) {
                    HapticManager.light()
                    authService.signOut()
                    dismiss()
                }
            } message: {
                Text("You can sign back in easily using your saved profile.")
            }
            .confirmationDialog("Forget Saved Password?", isPresented: $showForgetCachedConfirm) {
                Button("Forget & Sign Out", role: .destructive) {
                    if let pid = authService.currentProfile?.id {
                        authService.forgetPassword(for: pid)
                    }
                    authService.signOut()
                    dismiss()
                }
            } message: {
                Text("This will remove your saved password from this device's Keychain.")
            }
        }
    }
}

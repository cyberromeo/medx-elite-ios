import SwiftUI

public struct SettingsView: View {
    @ObservedObject var authService = AuthService.shared
    @State private var showSignOutConfirm = false
    @State private var showForgetCachedConfirm = false
    @State private var cacheCleared = false
    @State private var cacheSize: String = "Calculating…"
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                // MARK: - Current Profile
                if let profile = authService.currentProfile {
                    Section {
                        HStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .strokeBorder(profile.gradient, lineWidth: 2)
                                    .frame(width: 64, height: 64)

                                Circle()
                                    .fill(profile.gradient)
                                    .frame(width: 56, height: 56)

                                Text(String(profile.displayName.prefix(1)))
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text(profile.displayName)
                                    .font(MedxFont.headline(18))
                                Text("@\(profile.handle)")
                                    .font(MedxFont.caption(14))
                                    .foregroundColor(.secondary)
                                Text(profile.email)
                                    .font(MedxFont.caption(12))
                                    .foregroundColor(Color(uiColor: .tertiaryLabel))
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }

                // MARK: - Storage
                Section("Storage") {
                    HStack {
                        Label {
                            Text("Offline Cache")
                                .font(MedxFont.body(15))
                        } icon: {
                            Image(systemName: "internaldrive.fill")
                                .foregroundColor(MedxTheme.primaryBlue)
                        }
                        Spacer()
                        Text(cacheSize)
                            .font(MedxFont.mono(13))
                            .foregroundColor(.secondary)
                    }

                    Button {
                        Task {
                            await CacheManager.shared.clearAll()
                            HapticManager.success()
                            withAnimation {
                                cacheCleared = true
                                cacheSize = "0 KB"
                            }
                        }
                    } label: {
                        HStack {
                            Label {
                                Text("Clear Cache")
                                    .font(MedxFont.body(15))
                            } icon: {
                                Image(systemName: "trash")
                                    .foregroundColor(MedxTheme.warningOrange)
                            }
                            Spacer()
                            if cacheCleared {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(MedxTheme.successGreen)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                    }
                }

                // MARK: - Account Actions
                Section("Account") {
                    Button(role: .destructive) {
                        showSignOutConfirm = true
                    } label: {
                        Label {
                            Text("Sign Out")
                                .font(MedxFont.body(15))
                        } icon: {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .foregroundColor(MedxTheme.destructiveRed)
                        }
                    }

                    if let profile = authService.currentProfile, authService.hasSavedPassword(for: profile.id) {
                        Button(role: .destructive) {
                            showForgetCachedConfirm = true
                        } label: {
                            Label {
                                Text("Sign Out & Forget Password")
                                    .font(MedxFont.body(15))
                            } icon: {
                                Image(systemName: "key.slash")
                                    .foregroundColor(MedxTheme.destructiveRed)
                            }
                        }
                    }
                }

                // MARK: - App Info
                Section {
                    HStack {
                        Label {
                            Text("Version")
                                .font(MedxFont.body(15))
                        } icon: {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(MedxTheme.cyanAccent)
                        }
                        Spacer()
                        Text("1.0.0")
                            .font(MedxFont.mono(13))
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Label {
                            Text("Platform")
                                .font(MedxFont.body(15))
                        } icon: {
                            Image(systemName: "swift")
                                .foregroundColor(MedxTheme.warningOrange)
                        }
                        Spacer()
                        Text("Swift Native")
                            .font(MedxFont.caption(13))
                            .foregroundColor(.secondary)
                    }
                } footer: {
                    Text("MedX Elite · Built with SwiftUI")
                        .font(MedxFont.caption(11))
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(MedxFont.headline(16))
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
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
    }
}

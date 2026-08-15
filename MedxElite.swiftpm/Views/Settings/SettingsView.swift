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
            List {
                // Current Profile
                if let profile = authService.currentProfile {
                    Section {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(profile.gradient)
                                    .frame(width: 56, height: 56)
                                Text(String(profile.displayName.prefix(1)))
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.displayName)
                                    .font(.headline)
                                Text("@\(profile.handle)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text(profile.email)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Actions
                Section {
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
                            Spacer()
                            if cacheCleared {
                                Text("Cleared")
                                    .font(.caption.bold())
                                    .foregroundColor(.green)
                            }
                        }
                    }

                    Button(role: .destructive) {
                        showSignOutConfirm = true
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }

                    if let profile = authService.currentProfile, authService.hasSavedPassword(for: profile.id) {
                        Button(role: .destructive) {
                            showForgetCachedConfirm = true
                        } label: {
                            Label("Sign Out & Forget Password", systemImage: "key.slash")
                        }
                    }
                }

                // App Info
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                } footer: {
                    Text("Medx-elite for iOS · Swift Native")
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

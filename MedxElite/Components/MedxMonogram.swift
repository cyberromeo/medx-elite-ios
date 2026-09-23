import SwiftUI

// MARK: - Monogram
//
// The toolbar button, and the thing it replaces is worth naming: `ProfileSettingsButton` drew a
// `ProfileAvatarView` — a photo if one had been picked, otherwise a two-letter monogram over a
// two-stop `LinearGradient` inside a `strokeBorder` ring, watching `AvatarStore` for changes. Six
// toolbars, and a published store observed from all of them, to draw a 32pt circle.
//
// One circle, one letter, in the same face every number in the app is set in. The photo has a place —
// `ProfileSelectView`, where choosing between two people is the whole screen, and the duel header,
// where whose turn it is matters — and a navigation bar is not it.

public struct MedxMonogram: View {
    private let hue: Color
    private let diameter: CGFloat
    private let action: () -> Void

    /// The hue tracks the signed-in profile's accent; `nil` (the first frame after launch,
    /// before the session resolves) falls back to secondary, and the glyph — a `person` — is the
    /// same either way, so the button never changes *shape* a moment later.
    public init(profile: Profile?, diameter: CGFloat = 32, action: @escaping () -> Void) {
        self.hue = profile?.accentColor ?? .secondary
        self.diameter = diameter
        self.action = action
    }

    public var body: some View {
        Button {
            HapticManager.light()
            action()
        } label: {
            Image(systemName: "person.fill")
                .font(.system(size: diameter * 0.5, weight: .semibold))
                .foregroundStyle(hue)
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(MedxDS.sunken))
                // The tap target is the platform's 44pt regardless of how big the circle is.
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profile and settings")
        .accessibilityHint("Opens account, bookmarks, history and app settings")
    }
}

// MARK: - Toolbar convenience

/// The monogram wired to Settings, which is what all six toolbars want.
///
/// Holds its own presentation rather than reaching into `AppState.showSettings`: Settings is reachable
/// from every screen, and routing six toolbars through one shared flag means the sheet is owned by
/// whichever screen happened to be on top when it was set.
public struct MedxSettingsMonogram: View {
    @ObservedObject private var authService = AuthService.shared
    @State private var showSettings = false

    public init() {}

    public var body: some View {
        MedxMonogram(profile: authService.currentProfile) {
            showSettings = true
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
}

// MARK: - Home profile button
//
// Home (and the Tests tab) get their own profile control rather than the shared
// `MedxSettingsMonogram`. Two things it fixes:
//
//   * **Single glass container.** A toolbar already lays its items on one pane of glass, so
//     adding the button's *own* `.buttonStyle(.glass)` stacked a second container behind the
//     icon — the "two glass containers" bug. Dropping the explicit style leaves the toolbar's
//     single pane, and `.buttonBorderShape(.circle)` reshapes that pane from its default capsule
//     to a circle.
//   * **The real face.** It shows the signed-in profile's photo when one is set, and the demo
//     `person` glyph only as the fallback.

public struct HomeProfileButton: View {
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var avatars = AvatarStore.shared
    @ObservedObject private var medxTheme = MedxAccentThemeStore.shared
    @State private var showSettings = false

    public init() {}

    /// The demo glyph wears the app's accent, and `MedxAccentThemeStore` is observed so it
    /// repaints the moment the accent changes in Settings.
    private var hue: Color { MedxTheme.accent }

    /// The signed-in profile's photo, if one has been chosen.
    private var photo: UIImage? {
        guard let id = authService.currentProfile?.id else { return nil }
        return avatars.images[id]
    }

    public var body: some View {
        control.sheet(isPresented: $showSettings) { SettingsView() }
    }

    @ViewBuilder
    private var control: some View {
        if #available(iOS 26.0, *) {
            // No explicit `.buttonStyle(.glass)` — see the note above; the toolbar owns the one
            // container. `.buttonBorderShape(.circle)` turns its default capsule into a circle.
            Button(action: open) { face }
                .buttonBorderShape(.circle)
                .accessibilityLabel("Profile and settings")
                .accessibilityHint("Opens account, bookmarks, history and app settings")
        } else {
            // iOS 17: no toolbar glass to reshape, so the circle is drawn here.
            Button(action: open) {
                face
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(MedxDS.sunken))
                    .clipShape(Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Profile and settings")
            .accessibilityHint("Opens account, bookmarks, history and app settings")
        }
    }

    @ViewBuilder
    private var face: some View {
        if let photo {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                .frame(width: 30, height: 30)
                .clipShape(Circle())
        } else {
            Image(systemName: "person.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(hue)
        }
    }

    private func open() {
        HapticManager.light()
        showSettings = true
    }
}

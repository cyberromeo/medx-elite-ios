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
// Home gets its own profile control rather than the shared `MedxSettingsMonogram`. Dropped into a
// navigation bar on iOS 26, a toolbar button takes the bar's *default* glass container, and that
// default is a **capsule** — a pill drawn around a round glyph, which is what looked wrong on
// Home. Forcing `.buttonBorderShape(.circle)` puts the glass back to a clean circle: the same
// account-button shape iOS itself uses top-right of Settings and Music.
//
// Scoped to Home on purpose — the other five toolbars keep the shared monogram.

public struct HomeProfileButton: View {
    @ObservedObject private var authService = AuthService.shared
    @State private var showSettings = false

    public init() {}

    /// The signed-in profile's accent, or a neutral grey on the first frame before the session
    /// resolves. The glyph is the same either way, so the control never changes shape a beat later.
    private var hue: Color { authService.currentProfile?.accentColor ?? .secondary }

    public var body: some View {
        control.sheet(isPresented: $showSettings) { SettingsView() }
    }

    @ViewBuilder
    private var control: some View {
        if #available(iOS 26.0, *) {
            Button(action: open) {
                Image(systemName: "person.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(hue)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Profile and settings")
            .accessibilityHint("Opens account, bookmarks, history and app settings")
        } else {
            // iOS 17: the sunken-circle monogram look, no glass to reshape.
            Button(action: open) {
                Image(systemName: "person.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(hue)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(MedxDS.sunken))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Profile and settings")
            .accessibilityHint("Opens account, bookmarks, history and app settings")
        }
    }

    private func open() {
        HapticManager.light()
        showSettings = true
    }
}

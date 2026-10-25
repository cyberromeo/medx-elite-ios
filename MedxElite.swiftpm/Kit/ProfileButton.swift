import SwiftUI

/// The one way into Settings: a circle in the trailing slot of every tab root, showing the
/// signed-in profile's photo when one is set and a `person` glyph in the accent otherwise.
///
/// No `.buttonStyle(.glass)` of its own: the toolbar owns the glass, and `.buttonBorderShape(.circle)`
/// reshapes the toolbar's pane from its default capsule to a circle. The sheet it opens is hosted
/// once, by `MainTabView`, so six toolbars cannot each present their own copy over whichever
/// screen happened to be on top.
public struct MedxProfileButton: View {
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var avatars = AvatarStore.shared
    @ObservedObject private var medxTheme = MedxAccentThemeStore.shared

    public init() {}

    /// The signed-in profile's photo, if one has been chosen.
    private var photo: UIImage? {
        guard let id = authService.currentProfile?.id else { return nil }
        return avatars.images[id]
    }

    public var body: some View {
        Button(action: open) { face }
            .buttonBorderShape(.circle)
            .accessibilityLabel("Profile and settings")
            .accessibilityHint("Opens the exam, the daily goal, reminders and appearance")
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
                .font(.body.weight(.semibold))
                .foregroundStyle(MedxTheme.accent)
        }
    }

    private func open() {
        HapticManager.light()
        AppState.shared.showSettings = true
    }
}

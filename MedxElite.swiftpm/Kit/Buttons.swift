import SwiftUI

// Exactly two button treatments, both the platform's own Liquid Glass. The runner's bottom
// bar and every toolbar get their glass from the bar itself and use plain buttons inside it.

public extension View {
    /// The one primary action on a screen — Start, Submit, Join. Prominent glass, a capsule.
    func medxPrimary(size: ControlSize = .large) -> some View {
        self
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .controlSize(size)
    }

    /// A secondary action — Try again, Edit, a filter. Clear glass, a capsule.
    func medxSecondary(size: ControlSize = .regular) -> some View {
        self
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .controlSize(size)
    }
}

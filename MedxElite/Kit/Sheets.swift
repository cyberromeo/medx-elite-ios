import SwiftUI

public extension View {
    /// A task sheet — a mode picker, a builder, an edit: half height, grows to full, a drag
    /// indicator, and a page rather than a form card on iPad.
    func medxTaskSheet() -> some View {
        self
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationSizing(.page)
    }

    /// A full-height sheet that is a page of its own — Settings.
    func medxFullSheet() -> some View {
        self
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationSizing(.page)
    }
}

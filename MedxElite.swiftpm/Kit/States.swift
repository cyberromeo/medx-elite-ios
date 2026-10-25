import SwiftUI

// MARK: - Empty and failed

/// Nothing here, or nothing could be loaded: the system's own unavailable view, with one
/// optional action. The same shape on every screen, so an empty tab never reads as a bug.
public struct MedxEmptyState: View {
    private let title: String
    private let symbol: String
    private let message: String?
    private let actionTitle: String?
    private let action: (() -> Void)?

    public init(
        _ title: String,
        symbol: String,
        message: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.symbol = symbol
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            if let message {
                Text(message)
            }
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .medxSecondary()
            }
        }
    }
}

// MARK: - Loading

public extension View {
    /// The real layout, greyed, while its data is on the way — the shape of the page instead of
    /// a spinner in the middle of nothing. Tapping is off until it arrives.
    func medxLoading(_ isLoading: Bool) -> some View {
        self
            .redacted(reason: isLoading ? .placeholder : [])
            .disabled(isLoading)
    }
}

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

// MARK: - Placeholder rows

/// Rows of the right shape while a list loads — a tile, a title, a detail line, greyed — so the
/// page arrives already laid out instead of as a spinner in the middle of nothing.
public struct MedxPlaceholderRows: View {
    private let count: Int

    public init(count: Int = 6) {
        self.count = count
    }

    public var body: some View {
        ForEach(0..<count, id: \.self) { _ in
            HStack(spacing: MedxSpace.m) {
                MedxSymbolTile("square.fill", hue: MedxOutcome.pending, size: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text("A title about this long")
                    Text("A detail line")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)
        }
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}

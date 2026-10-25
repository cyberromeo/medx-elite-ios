import SwiftUI

// MARK: - The icon tile

/// An SF Symbol on a coloured squircle, the way Settings and Shortcuts draw theirs. The one
/// implementation: 29 pt in a list row, larger on a card, and it scales with the body text.
public struct MedxSymbolTile: View {
    private let symbol: String
    private let hue: Color
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 29

    public init(_ symbol: String, hue: Color, size: CGFloat = 29) {
        self.symbol = symbol
        self.hue = hue
        _size = ScaledMetric(wrappedValue: size, relativeTo: .body)
    }

    public var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.52, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(hue.gradient, in: RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A `Label` whose icon is a `MedxSymbolTile`, for settings-style rows.
public struct MedxTileLabel: View {
    private let title: String
    private let detail: String?
    private let symbol: String
    private let hue: Color

    public init(_ title: String, detail: String? = nil, symbol: String, hue: Color) {
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.hue = hue
    }

    public var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } icon: {
            MedxSymbolTile(symbol, hue: hue)
        }
        // The label colour even inside a `Button`, where `.primary` would mean the tint.
        .foregroundStyle(Color.primary)
    }
}

// MARK: - A feature row

/// Tile · title · detail · trailing — a row that opens something, in a `List` or on a card.
public struct MedxFeatureRow<Trailing: View>: View {
    private let title: String
    private let detail: String?
    private let symbol: String
    private let hue: Color
    private let trailing: Trailing

    public init(
        _ title: String,
        detail: String? = nil,
        symbol: String,
        hue: Color,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.hue = hue
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: MedxSpace.m) {
            MedxSymbolTile(symbol, hue: hue)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.primary)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: MedxSpace.s)
            trailing
        }
        .padding(.vertical, 2)
        // The label colour even inside a `Button`, where `.primary` would mean the tint.
        .foregroundStyle(Color.primary)
    }
}

public extension MedxFeatureRow where Trailing == EmptyView {
    init(_ title: String, detail: String? = nil, symbol: String, hue: Color) {
        self.init(title, detail: detail, symbol: symbol, hue: hue) { EmptyView() }
    }
}

/// The system's grouped-list chevron, for a row drawn outside a `NavigationLink`.
public struct MedxRowChevron: View {
    public init() {}

    public var body: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }
}

// MARK: - A heading above cards

/// The grouped-list section voice, for a heading above cards in a `ScrollView`. A `List`
/// screen uses `Section` headers and never this.
public struct MedxHeading<Trailing: View>: View {
    private let title: String
    private let trailing: Trailing

    public init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.bold))
            Spacer(minLength: MedxSpace.s)
            trailing
        }
        .accessibilityAddTraits(.isHeader)
    }
}

public extension MedxHeading where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title) { EmptyView() }
    }
}

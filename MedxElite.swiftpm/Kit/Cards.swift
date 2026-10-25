import SwiftUI

/// A dashboard surface: the system's grouped cell, free-standing. Home has a few of these;
/// every other screen is a `List` and draws no card of its own. A `tint` makes it the one
/// coloured surface a screen is allowed — the exam countdown — and the content takes the ink
/// that reads on that tint.
public struct MedxCard<Content: View>: View {
    private let tint: Color?
    private let content: Content

    @Environment(\.colorScheme) private var scheme

    public init(tint: Color? = nil, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.content = content()
    }

    public var body: some View {
        content
            .foregroundStyle(tint.map { $0.medxInkOnFill(in: scheme) } ?? Color.primary)
            .padding(MedxSpace.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: MedxRadius.card, style: .continuous))
    }

    private var fill: AnyShapeStyle {
        if let tint {
            return AnyShapeStyle(tint.gradient)
        }
        return AnyShapeStyle(Color(uiColor: .secondarySystemGroupedBackground))
    }
}

/// The card's shape, for a `contentShape` or an overlay that has to match it.
public extension MedxCard {
    static var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: MedxRadius.card, style: .continuous)
    }
}

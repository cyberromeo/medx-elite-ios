import SwiftUI

// MARK: - A figure

/// A number in the rounded voice. Monospaced digits so a clock or a counter never nudges its
/// neighbours, a numeric transition so a changing figure rolls rather than cuts, and a text style
/// rather than a point size so it follows Dynamic Type.
public struct MedxFigure: View {
    private let text: String
    private let style: Font.TextStyle
    private let weight: Font.Weight

    public init(_ text: String, style: Font.TextStyle = .title2, weight: Font.Weight = .bold) {
        self.text = text
        self.style = style
        self.weight = weight
    }

    public var body: some View {
        Text(text)
            .font(.system(style, design: .rounded).weight(weight))
            .monospacedDigit()
            .contentTransition(.numericText())
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}

// MARK: - A stat tile

/// icon · value · label — the one implementation of a figure with a caption. Quiet: the glyph
/// carries the colour, the figure is the label colour, so a row of them does not read as a row
/// of alerts.
public struct MedxStatTile: View {
    private let value: String
    private let label: String
    private let symbol: String
    private let hue: Color

    public init(_ value: String, label: String, symbol: String, hue: Color) {
        self.value = value
        self.label = label
        self.symbol = symbol
        self.hue = hue
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: MedxSpace.xs) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(hue)
            MedxFigure(value)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}

/// Stat tiles side by side, stacked at an accessibility text size where three abreast would
/// wrap every caption to three lines.
public struct MedxStatRow<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: MedxSpace.m) { content }
        } else {
            HStack(alignment: .top, spacing: MedxSpace.m) { content }
        }
    }
}

// MARK: - The ring

/// The one ring. A track, an arc that fills clockwise from the top, and whatever sits in the
/// middle. Animates the arc only, and not under Reduce Motion.
public struct MedxRing<Label: View>: View {
    private let fraction: Double
    private let tint: Color
    private let lineWidth: CGFloat
    private let label: Label

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(fraction: Double, tint: Color, lineWidth: CGFloat = 10, @ViewBuilder label: () -> Label) {
        self.fraction = fraction
        self.tint = tint
        self.lineWidth = lineWidth
        self.label = label()
    }

    public var body: some View {
        let clamped = min(max(fraction, 0), 1)
        ZStack {
            Circle()
                .stroke(tint.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(clamped, 0.003))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .snappy(duration: 0.45), value: clamped)
            label
                .padding(lineWidth + 4)
        }
        .accessibilityHidden(true)
    }
}

public extension MedxRing where Label == EmptyView {
    init(fraction: Double, tint: Color, lineWidth: CGFloat = 10) {
        self.init(fraction: fraction, tint: tint, lineWidth: lineWidth) { EmptyView() }
    }
}

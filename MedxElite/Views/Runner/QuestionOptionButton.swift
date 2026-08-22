import SwiftUI

/// One answer row. Reads as a native selectable cell: neutral fill, a hairline border, a
/// letter badge and a radio glyph. State is carried by the badge and the border, not by a
/// tinted glass sheet.
public struct QuestionOptionButton: View {
    public let option: QuestionOption
    public let isChosen: Bool
    public let isCorrect: Bool
    public let isRevealed: Bool
    public let isLocked: Bool
    public let onSelect: () -> Void

    public init(
        option: QuestionOption,
        isChosen: Bool,
        isCorrect: Bool,
        isRevealed: Bool,
        isLocked: Bool,
        onSelect: @escaping () -> Void
    ) {
        self.option = option
        self.isChosen = isChosen
        self.isCorrect = isCorrect
        self.isRevealed = isRevealed
        self.isLocked = isLocked
        self.onSelect = onSelect
    }

    public var body: some View {
        // Haptics are owned by the runner so revision mode doesn't buzz twice.
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 12) {
                letterBadge

                // `interactive: false` — a button nested inside this one would never fire,
                // and text selection would eat the row's tap.
                HTMLRichTextView(
                    html: option.text,
                    fontSize: 16,
                    weight: .regular,
                    maxImageHeight: 180,
                    interactive: false
                )
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                trailingGlyph
                    .padding(.top, 2)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: 56, alignment: .center)
            .medxTile(cornerRadius: 14, accentColor: stateColor, isSelected: isEmphasized)
            .opacity(isDimmed ? 0.55 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(BouncyButtonStyle())
        .disabled(isLocked)
        .animation(.easeOut(duration: 0.16), value: isChosen)
        .animation(.easeOut(duration: 0.16), value: isRevealed)
        .accessibilityLabel("Option \(option.label)")
        .accessibilityValue(accessibilityState)
        .accessibilityAddTraits(isChosen ? [.isSelected] : [])
    }

    // MARK: - Pieces

    private var letterBadge: some View {
        Text(option.label)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(isFilledBadge ? Color.white : Color.primary)
            .frame(width: 28, height: 28)
            .background(
                Circle().fill(isFilledBadge ? (stateColor ?? Color.accentColor) : MedxSurface.fieldFill)
            )
            .overlay(
                Circle().strokeBorder(
                    isFilledBadge ? Color.clear : Color(uiColor: .quaternaryLabel),
                    lineWidth: 1
                )
            )
    }

    @ViewBuilder
    private var trailingGlyph: some View {
        if isRevealed, isCorrect {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(MedxTheme.successGreen)
        } else if isRevealed, isChosen {
            Image(systemName: "xmark.circle.fill")
                .font(.title3)
                .foregroundStyle(MedxTheme.destructiveRed)
        } else if isChosen {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
        } else if !isRevealed {
            Image(systemName: "circle")
                .font(.title3)
                .foregroundStyle(Color(uiColor: .quaternaryLabel))
        }
    }

    // MARK: - Derived state

    /// The colour that describes this row's current meaning, or nil when it is neutral.
    private var stateColor: Color? {
        if isRevealed {
            if isCorrect { return MedxTheme.successGreen }
            if isChosen { return MedxTheme.destructiveRed }
            return nil
        }
        return isChosen ? Color.accentColor : nil
    }

    private var isEmphasized: Bool {
        isChosen || (isRevealed && isCorrect)
    }

    private var isFilledBadge: Bool {
        stateColor != nil
    }

    /// Once the key is out, rows that are neither the answer nor the pick step back.
    private var isDimmed: Bool {
        isRevealed && !isChosen && !isCorrect
    }

    private var accessibilityState: String {
        if isRevealed {
            if isCorrect { return isChosen ? "Your answer, correct" : "Correct answer" }
            if isChosen { return "Your answer, incorrect" }
            return "Not selected"
        }
        return isChosen ? "Selected" : "Not selected"
    }
}

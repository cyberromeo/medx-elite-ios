import SwiftUI

public struct QuestionOptionButton: View {
    public let option: QuestionOption
    public let isChosen: Bool
    public let isCorrect: Bool
    public let isRevealed: Bool
    public let isLocked: Bool
    public let accent: Color
    public let isDimmed: Bool
    public let onSelect: () -> Void

    public init(
        option: QuestionOption,
        isChosen: Bool,
        isCorrect: Bool,
        isRevealed: Bool,
        isLocked: Bool,
        accent: Color = MedxTheme.primaryBlue,
        isDimmed: Bool = false,
        onSelect: @escaping () -> Void
    ) {
        self.option = option
        self.isChosen = isChosen
        self.isCorrect = isCorrect
        self.isRevealed = isRevealed
        self.isLocked = isLocked
        self.accent = accent
        self.isDimmed = isDimmed
        self.onSelect = onSelect
    }

    public var body: some View {
        // Haptics are owned by the runner so revision mode doesn't buzz twice.
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: 13) {
                letterBadge

                HTMLRichTextView(html: option.text, fontSize: 15, weight: .regular)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)

                Spacer(minLength: 0)

                trailingGlyph
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: 58, alignment: .center)
            .liquidGlassTile(cornerRadius: 18, accentColor: stateColor, isSelected: isEmphasized)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(stateColor?.opacity(0.85) ?? Color.clear, lineWidth: isEmphasized ? 1.5 : 0)
            )
            .opacity(isDimmed ? 0.55 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(BouncyButtonStyle())
        .disabled(isLocked)
        .animation(.easeOut(duration: 0.18), value: isChosen)
        .animation(.easeOut(duration: 0.18), value: isRevealed)
        .accessibilityLabel("Option \(option.label)")
        .accessibilityValue(accessibilityState)
        .accessibilityAddTraits(isChosen ? [.isSelected] : [])
    }

    // MARK: - Pieces

    private var letterBadge: some View {
        Text(option.label)
            .font(MedxFont.mono(14, weight: .bold))
            .foregroundStyle(isFilledBadge ? Color.white : Color.primary)
            .frame(width: 30, height: 30)
            .background(
                Circle().fill(isFilledBadge ? (stateColor ?? accent) : Color(uiColor: .tertiarySystemFill))
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
                .foregroundStyle(accent)
        } else if !isRevealed {
            // A real radio affordance: an untouched option used to show nothing at all.
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
        return isChosen ? accent : nil
    }

    private var isEmphasized: Bool {
        isChosen || (isRevealed && isCorrect)
    }

    private var isFilledBadge: Bool {
        stateColor != nil
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

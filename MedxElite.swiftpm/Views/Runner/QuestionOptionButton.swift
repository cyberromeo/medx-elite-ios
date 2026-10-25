import SwiftUI

/// One answer row: a lettered badge, the option's text, and a glyph only when it means
/// something. The row's own fill is the resting state; a chosen or revealed row takes its
/// outcome colour as a border and a wash, which reads at a glance.
public struct QuestionOptionButton: View {
    public let option: QuestionOption
    /// Position in the question, used only to letter a row whose `label` the backend left blank.
    public let index: Int
    public let isChosen: Bool
    public let isCorrect: Bool
    public let isRevealed: Bool
    public let isLocked: Bool
    public let onSelect: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        option: QuestionOption,
        index: Int = 0,
        isChosen: Bool,
        isCorrect: Bool,
        isRevealed: Bool,
        isLocked: Bool,
        onSelect: @escaping () -> Void
    ) {
        self.option = option
        self.index = index
        self.isChosen = isChosen
        self.isCorrect = isCorrect
        self.isRevealed = isRevealed
        self.isLocked = isLocked
        self.onSelect = onSelect
    }

    private var letter: String {
        MedxOptionLetter.of(option, at: index)
    }

    public var body: some View {
        // Haptics are owned by the runner so revision mode does not buzz twice.
        Button(action: onSelect) {
            HStack(alignment: .medxFirstLine, spacing: MedxSpace.m) {
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
                .medxFirstLineGuide(fontSize: 16)
                .layoutPriority(1)

                // Always the same slot, so the words do not shift when a glyph pops in.
                trailingGlyph
                    .frame(width: 24, height: 24)
            }
            .padding(.horizontal, MedxSpace.l)
            .padding(.vertical, MedxSpace.l)
            .frame(minHeight: 56)
            .medxOptionSurface(state: stateColor)
            .opacity(isDimmed ? 0.5 : 1)
            .contentShape(RoundedRectangle(cornerRadius: MedxRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isLocked)
        .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: isChosen)
        .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: isRevealed)
        .accessibilityLabel("Option \(letter)")
        .accessibilityValue(accessibilityState)
        .accessibilityAddTraits(isChosen ? [.isSelected] : [])
    }

    // MARK: - Pieces

    private var letterBadge: some View {
        Text(letter)
            .font(.system(.subheadline, design: .rounded).weight(.bold))
            .foregroundStyle(stateColor == nil ? Color.primary : Color.white)
            .frame(width: 32, height: 32)
            .background(stateColor ?? Color(uiColor: .tertiarySystemFill), in: Circle())
    }

    /// Only ever drawn when it means something: the pick, or the key once it is out.
    @ViewBuilder
    private var trailingGlyph: some View {
        Group {
            if isRevealed, isCorrect {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(MedxOutcome.correct)
            } else if isRevealed, isChosen {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(MedxOutcome.wrong)
            } else if isChosen {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(MedxTheme.accent)
            }
        }
        .font(.title3)
        .transition(.scale(scale: 0.4).combined(with: .opacity))
    }

    // MARK: - Derived state

    /// The colour that describes this row's current meaning, or nil when it is neutral.
    private var stateColor: Color? {
        if isRevealed {
            if isCorrect { return MedxOutcome.correct }
            if isChosen { return MedxOutcome.wrong }
            return nil
        }
        return isChosen ? MedxTheme.accent : nil
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

/// The letter shown beside an option.
///
/// Authored labels are used as given — the two banks both supply `A`…`D`, and a paper that
/// deliberately labels its options `i`…`iv` should keep them. A blank falls back to the position,
/// because an empty badge looks like a bug, and every option list in the app asks this one
/// question so they cannot drift apart.
public enum MedxOptionLetter {
    public static func of(_ option: QuestionOption, at index: Int) -> String {
        let trimmed = option.label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return at(index)
    }

    /// `0 → "A"`, wrapping past 26 rather than running off the end of the alphabet.
    public static func at(_ index: Int) -> String {
        guard index >= 0 else { return "?" }
        let scalar = UnicodeScalar(65 + index % 26) ?? "?"
        return String(Character(scalar))
    }
}

extension View {
    /// An answer row's surface: the grouped cell at rest, and a border only when the row means
    /// something.
    @ViewBuilder
    func medxOptionSurface(state: Color?) -> some View {
        let shape = RoundedRectangle(cornerRadius: MedxRadius.control, style: .continuous)

        if let state {
            self
                .background(state.opacity(0.12), in: shape)
                .overlay {
                    shape
                        .strokeBorder(state.opacity(0.9), lineWidth: 1.5)
                        .allowsHitTesting(false)
                }
        } else {
            self
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: shape)
        }
    }
}

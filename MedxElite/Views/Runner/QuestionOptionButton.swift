import SwiftUI

/// One answer row. Reads as a native selectable cell: an opaque fill one step off the card, a
/// hairline border, a letter badge and a state glyph. State is carried by the badge and by a real
/// 1.5pt border in the state's colour — not by a tinted sheet of glass, which is what these were
/// and which could not be relied on to out-shout the three rows around it.
public struct QuestionOptionButton: View {
    public let option: QuestionOption
    /// Position in the question, used only to letter a row whose `label` the backend left blank.
    public let index: Int
    public let isChosen: Bool
    public let isCorrect: Bool
    public let isRevealed: Bool
    public let isLocked: Bool
    public let onSelect: () -> Void

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

    /// The authored letter, or the position's own when there is none — a blank badge reads as a
    /// rendering fault, and `MedxOptionLetter` is the same rule every option list in the app uses.
    private var letter: String {
        MedxOptionLetter.of(option, at: index)
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
            .padding(.vertical, 13)
            .frame(minHeight: 58, alignment: .center)
            .medxTile(cornerRadius: MedxSurface.tileRadius, accentColor: stateColor, isSelected: isEmphasized)
            .opacity(isDimmed ? 0.5 : 1)
            .contentShape(RoundedRectangle(cornerRadius: MedxSurface.tileRadius, style: .continuous))
        }
        .buttonStyle(BouncyButtonStyle())
        .disabled(isLocked)
        .animation(.easeOut(duration: 0.16), value: isChosen)
        .animation(MedxMotion.snap, value: isRevealed)
        .accessibilityLabel("Option \(letter)")
        .accessibilityValue(accessibilityState)
        .accessibilityAddTraits(isChosen ? [.isSelected] : [])
    }

    // MARK: - Pieces

    /// The letter, on its own small surface.
    ///
    /// A stateful row inks it solid — a green A on a correct answer has to survive being glanced
    /// at — while a neutral one sits one step brighter than the row it is on, so it still reads
    /// as a badge rather than as part of the fill.
    private var letterBadge: some View {
        Text(letter)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(isFilledBadge ? MedxCandy.onSolid : Color.primary)
            .frame(width: 30, height: 30)
            .background {
                if isFilledBadge {
                    Circle().fill(stateColor ?? MedxTheme.accent)
                }
            }
            .medxBadgeInk(plain: !isFilledBadge)
    }

    /// Only ever drawn when it means something.
    ///
    /// There used to be a hollow `circle` on every unpicked row — four empty rings per question,
    /// forty questions a paper, saying nothing the lettered badge on the left had not already
    /// said. The row's own fill and its letter are the affordance; the glyph is reserved for
    /// state, and it pops in rather than appearing because the pop *is* the feedback.
    @ViewBuilder
    private var trailingGlyph: some View {
        Group {
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
                    .foregroundStyle(MedxTheme.accent)
            }
        }
        .transition(.scale(scale: 0.4).combined(with: .opacity))
    }

    // MARK: - Derived state

    /// The colour that describes this row's current meaning, or nil when it is neutral.
    private var stateColor: Color? {
        if isRevealed {
            if isCorrect { return MedxTheme.successGreen }
            if isChosen { return MedxTheme.destructiveRed }
            return nil
        }
        return isChosen ? MedxTheme.accent : nil
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

private extension View {
    /// The badge's own surface, added only where the badge is standing on its own — a stateful
    /// one already has an opaque circle of its state colour underneath and putting anything over
    /// that would just mute it.
    @ViewBuilder
    func medxBadgeInk(plain: Bool) -> some View {
        if plain {
            self.medxSurface(
                Circle(),
                MedxSurfaceSpec(fill: MedxInk.field)
            )
        } else {
            self
        }
    }
}

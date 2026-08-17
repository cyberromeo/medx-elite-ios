import SwiftUI

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
        Button {
            if !isLocked {
                HapticManager.selection()
                onSelect()
            }
        } label: {
            HStack(alignment: .center, spacing: 14) {
                // Option Letter Badge
                Text(option.label)
                    .font(MedxFont.mono(14, weight: .bold))
                    .foregroundColor(letterTextColor)
                    .frame(width: 32, height: 32)
                    .background(letterBgColor)
                    .clipShape(Circle())
                    .shadow(color: (isRevealed ? (isCorrect ? MedxTheme.successGreen : MedxTheme.destructiveRed) : (isChosen ? MedxTheme.primaryBlue : Color.clear)).opacity(0.4), radius: 4)

                // Option HTML Text
                HTMLRichTextView(html: option.text, fontSize: 15, weight: .regular)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)

                Spacer(minLength: 0)

                // State indicator icon
                if isRevealed {
                    if isCorrect {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(MedxTheme.successGreen)
                            .symbolEffect(.pulse)
                    } else if isChosen {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(MedxTheme.destructiveRed)
                    }
                } else if isChosen {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(MedxTheme.primaryBlue)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(minHeight: 56, alignment: .center)
            .liquidGlassTile(
                cornerRadius: 18,
                accentColor: activeAccentColor,
                isSelected: isChosen || (isRevealed && isCorrect)
            )
        }
        .buttonStyle(BouncyButtonStyle())
        .disabled(isLocked)
    }

    private var activeAccentColor: Color? {
        if isRevealed {
            if isCorrect { return MedxTheme.successGreen }
            if isChosen { return MedxTheme.destructiveRed }
        } else if isChosen {
            return MedxTheme.primaryBlue
        }
        return nil
    }

    private var letterTextColor: Color {
        if isRevealed {
            if isCorrect || isChosen { return .white }
        } else if isChosen {
            return .white
        }
        return .primary
    }

    private var letterBgColor: Color {
        if isRevealed {
            if isCorrect { return MedxTheme.successGreen }
            if isChosen { return MedxTheme.destructiveRed }
        } else if isChosen {
            return MedxTheme.primaryBlue
        }
        return Color.primary.opacity(0.08)
    }
}

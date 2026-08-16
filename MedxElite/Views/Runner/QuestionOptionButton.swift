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
            HStack(alignment: .top, spacing: 14) {
                // Option Letter Badge
                Text(option.label)
                    .font(MedxFont.mono(14, weight: .bold))
                    .foregroundColor(letterTextColor)
                    .frame(width: 32, height: 32)
                    .background(letterBgColor)
                    .clipShape(Circle())

                // Option HTML Text
                HTMLRichTextView(html: option.text, fontSize: 15, weight: .regular)
                    .multilineTextAlignment(.leading)

                Spacer()

                // State indicator icon
                if isRevealed {
                    if isCorrect {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(MedxTheme.successGreen)
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
            .padding(16)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(cardBorderColor, lineWidth: 1.5)
            )
            .shadow(color: isChosen ? MedxTheme.primaryBlue.opacity(0.15) : Color.clear, radius: 8, x: 0, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isLocked)
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

    private var cardBackground: Color {
        if isRevealed {
            if isCorrect { return MedxTheme.successGreen.opacity(0.12) }
            if isChosen { return MedxTheme.destructiveRed.opacity(0.12) }
        } else if isChosen {
            return MedxTheme.primaryBlue.opacity(0.1)
        }
        return Color.primary.opacity(0.03)
    }

    private var cardBorderColor: Color {
        if isRevealed {
            if isCorrect { return MedxTheme.successGreen.opacity(0.6) }
            if isChosen { return MedxTheme.destructiveRed.opacity(0.6) }
        } else if isChosen {
            return MedxTheme.primaryBlue.opacity(0.6)
        }
        return Color.primary.opacity(0.06)
    }
}

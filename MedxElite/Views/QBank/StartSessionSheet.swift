import SwiftUI

public struct StartSessionSheet: View {
    public let title: String
    public let subtitle: String
    public let questionCount: Int
    public var onStart: (SittingMode) -> Void
    @Environment(\.dismiss) private var dismiss

    public init(title: String, subtitle: String, questionCount: Int, onStart: @escaping (SittingMode) -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.questionCount = questionCount
        self.onStart = onStart
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()

                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Text(title)
                            .font(MedxFont.rounded(22, weight: .bold))
                            .multilineTextAlignment(.center)

                        Text("\(subtitle) · \(questionCount) questions")
                            .font(MedxFont.rounded(14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 16)

                    // Mode Selection Options
                    VStack(spacing: 16) {
                        ModeCard(
                            mode: .revision,
                            icon: "bolt.fill",
                            accentColor: MedxTheme.primaryPurple,
                            durationText: "\(questionCount) mins (60s / question)"
                        ) {
                            HapticManager.medium()
                            dismiss()
                            onStart(.revision)
                        }

                        ModeCard(
                            mode: .exam,
                            icon: "timer",
                            accentColor: MedxTheme.primaryBlue,
                            durationText: "\(questionCount) mins total timer"
                        ) {
                            HapticManager.medium()
                            dismiss()
                            onStart(.exam)
                        }
                    }
                    .padding(.horizontal, 20)

                    Spacer()
                }
            }
            .navigationTitle("Start Sitting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.height(460)])
    }
}

private struct ModeCard: View {
    let mode: SittingMode
    let icon: String
    let accentColor: Color
    let durationText: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(accentColor.opacity(0.15))
                        .frame(width: 48, height: 48)
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundColor(accentColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(mode.displayName)
                            .font(MedxFont.rounded(17, weight: .bold))
                            .foregroundColor(.primary)

                        Spacer()

                        Text(durationText)
                            .font(MedxFont.monospacedDigits(12, weight: .semibold))
                            .foregroundColor(accentColor)
                    }

                    Text(mode.description)
                        .font(MedxFont.rounded(13, weight: .regular))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(18)
            .liquidGlassCard(cornerRadius: 20, glowColor: accentColor)
        }
        .buttonStyle(BouncyButtonStyle())
    }
}

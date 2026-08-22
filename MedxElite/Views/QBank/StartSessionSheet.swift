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

                ScrollView {
                    VStack(spacing: 22) {
                        VStack(spacing: 10) {
                            Text(title)
                                .font(MedxFont.title(22))
                                .multilineTextAlignment(.center)

                            HStack(spacing: 8) {
                                if !subtitle.isEmpty {
                                    Text(subtitle)
                                        .font(MedxFont.caption(14))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Text("\(questionCount) questions")
                                    .font(MedxFont.mono(11, weight: .bold))
                                    .foregroundStyle(MedxTheme.primaryBlue)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(MedxTheme.primaryBlue.opacity(0.14), in: Capsule())
                            }
                        }
                        .padding(.top, 10)
                        .padding(.horizontal, 20)

                        Text("Pick how you want to sit this paper")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        VStack(spacing: 14) {
                            ModeCard(
                                mode: .revision,
                                icon: "bolt.fill",
                                accentColor: MedxTheme.primaryPurple,
                                durationText: "60s / question"
                            ) {
                                HapticManager.medium()
                                dismiss()
                                onStart(.revision)
                            }

                            ModeCard(
                                mode: .exam,
                                icon: "timer",
                                accentColor: MedxTheme.primaryBlue,
                                durationText: "\(questionCount) min total"
                            ) {
                                HapticManager.medium()
                                dismiss()
                                onStart(.exam)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 24)
                }
                .scrollBounceBehavior(.basedOnSize)
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
        .presentationDetents([.height(460), .large])
        .presentationDragIndicator(.visible)
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
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(accentColor.opacity(0.15))
                        .frame(width: 46, height: 46)
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(accentColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(mode.displayName)
                            .font(MedxFont.headline(17))
                            .foregroundStyle(.primary)

                        Text(durationText)
                            .font(MedxFont.mono(11, weight: .semibold))
                            .foregroundStyle(accentColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(accentColor.opacity(0.12), in: Capsule())
                    }

                    Text(mode.description)
                        .font(MedxFont.caption(13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlassCard(cornerRadius: 20, glowColor: accentColor)
            .contentShape(Rectangle())
        }
        .buttonStyle(BouncyButtonStyle())
        .accessibilityLabel("\(mode.displayName) mode")
        .accessibilityHint("\(mode.description). \(durationText).")
    }
}

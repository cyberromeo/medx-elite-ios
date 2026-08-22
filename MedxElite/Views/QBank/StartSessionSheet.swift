import SwiftUI

/// Mode picker shown before a sitting starts. Two choices, described plainly.
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
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 6) {
                        Text(title)
                            .font(.title3.weight(.semibold))
                            .multilineTextAlignment(.center)

                        Text(headerDetail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)

                    VStack(spacing: 12) {
                        ModeCard(
                            mode: .revision,
                            icon: "bolt.fill",
                            tint: MedxTheme.tealAccent,
                            durationText: "60s per question"
                        ) {
                            start(.revision)
                        }

                        ModeCard(
                            mode: .exam,
                            icon: "timer",
                            tint: MedxTheme.primaryBlue,
                            durationText: "\(questionCount) min total"
                        ) {
                            start(.exam)
                        }
                    }
                }
                .padding(.horizontal, MedxSurface.gutter)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(MedxSurface.groupedBackground.ignoresSafeArea())
            .navigationTitle("Start Sitting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.height(430), .large])
        .presentationDragIndicator(.visible)
    }

    private var headerDetail: String {
        var parts: [String] = []
        if !subtitle.isEmpty { parts.append(subtitle) }
        parts.append("\(questionCount) questions")
        return parts.joined(separator: " · ")
    }

    private func start(_ mode: SittingMode) {
        HapticManager.medium()
        dismiss()
        onStart(mode)
    }
}

private struct ModeCard: View {
    let mode: SittingMode
    let icon: String
    let tint: Color
    let durationText: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 40, height: 40)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(mode.displayName)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        MedxChip(durationText, tint: tint)
                    }

                    Text(mode.description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                MedxDisclosure()
                    .padding(.top, 4)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .medxCard()
            .contentShape(RoundedRectangle(cornerRadius: MedxSurface.cardRadius, style: .continuous))
        }
        .buttonStyle(BouncyButtonStyle())
        .accessibilityLabel("\(mode.displayName)")
        .accessibilityHint("\(mode.description). \(durationText).")
    }
}

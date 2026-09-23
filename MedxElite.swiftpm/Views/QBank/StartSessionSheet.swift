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
                        MedxSymbolMark("target", hue: MedxCandy.lime, size: 52)
                            .padding(.bottom, 2)

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
                            symbol: "bolt.fill",
                            tint: MedxCandy.mint,
                            durationText: "60s per question"
                        ) {
                            start(.revision)
                        }

                        ModeCard(
                            mode: .exam,
                            symbol: "hourglass",
                            tint: MedxCandy.tangerine,
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
            // No opaque page fill: a partial sheet is Liquid Glass on iOS 26, and painting over it
            // was hiding that. The mode cards stay as normal content on top of the glass.
            .scrollContentBackground(.hidden)
            .navigationTitle("Start Sitting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.height(486), .large])
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
    let symbol: String
    let tint: Color
    let durationText: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                MedxSymbolMark(symbol, hue: tint, size: 40)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(mode.displayName)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        MedxPill(durationText, hue: tint)
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

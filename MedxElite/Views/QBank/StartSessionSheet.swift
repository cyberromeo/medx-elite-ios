import SwiftUI

/// Mode picker shown before a sitting starts. Two choices, described plainly.
///
/// One of the two places in the app where a *content-shaped* rectangle is glass. A sheet floats
/// over the screen it was raised from, so there is a real page behind these two cards to bend —
/// which is the only condition under which glass reads as glass rather than as haze. On a
/// scrolling page the same card would have nothing but the backdrop behind it, and that is why
/// every other card in the app is now opaque.
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
                VStack(alignment: .leading, spacing: 20) {
                    // The nav bar already says "Start Sitting" and the module's own name is what the
                    // student just tapped, so this is only the shape of the sitting. There used to be a
                    // 52pt lime target glyph over a centred restatement of the title above it.
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(questionCount)")
                            .font(MedxType.display)
                        Text(headerDetail)
                            .medxTag()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    ModeCard(
                        mode: .revision,
                        symbol: "bolt.fill",
                        durationText: "60s per question"
                    ) {
                        start(.revision)
                    }

                    ModeCard(
                        mode: .exam,
                        symbol: "hourglass",
                        durationText: "\(questionCount) min total"
                    ) {
                        start(.exam)
                    }
                }
                .padding(.horizontal, MedxDS.gutter)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .medxPage()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var headerDetail: String {
        var parts = ["questions"]
        if !subtitle.isEmpty { parts.append(subtitle) }
        return parts.joined(separator: " · ")
    }

    private func start(_ mode: SittingMode) {
        HapticManager.medium()
        dismiss()
        onStart(mode)
    }
}

/// **This is the popup the user asked to keep in glass**, and one of the three places it survives. A
/// sheet floats over the screen it was raised from, so these two cards have a real page behind them to
/// bend — the only condition under which glass reads as glass rather than as haze.
private struct ModeCard: View {
    let mode: SittingMode
    let symbol: String
    let durationText: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 5) {
                    Text(mode.displayName)
                        .font(MedxType.heading)
                        .foregroundStyle(.primary)

                    Text(durationText)
                        .medxTag()

                    Text(mode.description)
                        .font(MedxType.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .medxSheetCard()
            .contentShape(MedxDS.shape(MedxDS.card))
        }
        .buttonStyle(MedxPressStyle())
        .accessibilityLabel("\(mode.displayName)")
        .accessibilityHint("\(mode.description). \(durationText).")
    }
}

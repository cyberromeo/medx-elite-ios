import SwiftUI

/// The one mode picker. A module, a batch paper and a Marrow paper all ask the same question
/// before a sitting starts — revision or exam — so they share this sheet; what differs is only
/// the line under each mode, which a caller overrides to say what *this* paper's exam clock does.
///
/// The sheet never starts the sitting itself. It reports the pick and dismisses, and the host
/// starts the runner from the sheet's `onDismiss`, once it has gone: raising a full-screen cover
/// in the same update that dismisses a sheet hands the cover to the sheet's presentation on
/// iOS 26, and the runner then looks alive but never updates — the "dead Next" of September 2026.
public struct StartSessionSheet: View {
    public let title: String
    public let subtitle: String
    public let questionCount: Int
    /// What exam mode does for this paper, when the default one-minute-a-question line is wrong.
    public let examDetail: String?
    /// What revision mode does, when there is something to say — a paper with no answer key.
    public let revisionDetail: String?
    /// Previous sittings of the same paper, if any.
    public let record: MedxPaperRecord?
    public var onStart: (SittingMode) -> Void

    @Environment(\.dismiss) private var dismiss

    public init(
        title: String,
        subtitle: String,
        questionCount: Int,
        examDetail: String? = nil,
        revisionDetail: String? = nil,
        record: MedxPaperRecord? = nil,
        onStart: @escaping (SittingMode) -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.questionCount = questionCount
        self.examDetail = examDetail
        self.revisionDetail = revisionDetail
        self.record = record
        self.onStart = onStart
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    modeRow(
                        .revision,
                        symbol: "bolt.fill",
                        hue: MedxFeature.qbank.color,
                        detail: revisionDetail ?? Self.defaultRevisionDetail
                    )
                    modeRow(
                        .exam,
                        symbol: "timer",
                        hue: MedxFeature.tests.color,
                        detail: examDetail ?? Self.defaultExamDetail(questions: questionCount)
                    )
                } header: {
                    Text(header)
                }

                if let record {
                    Section("Your sittings") {
                        LabeledContent("Best score", value: "\(record.bestScore) of \(record.total)")
                        LabeledContent("Sittings", value: "\(record.sittings)")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
        .medxTaskSheet()
    }

    private var header: String {
        var parts: [String] = []
        if !subtitle.isEmpty { parts.append(subtitle) }
        parts.append("\(MedxFormat.count(questionCount)) questions")
        return parts.joined(separator: " · ")
    }

    private func modeRow(_ mode: SittingMode, symbol: String, hue: Color, detail: String) -> some View {
        Button {
            HapticManager.medium()
            onStart(mode)
            dismiss()
        } label: {
            MedxFeatureRow(Self.title(for: mode), detail: detail, symbol: symbol, hue: hue) {
                MedxRowChevron()
            }
        }
        .accessibilityLabel(Self.title(for: mode))
        .accessibilityHint(detail)
    }

    static func title(for mode: SittingMode) -> String {
        switch mode {
        case .exam: return "Exam mode"
        case .revision: return "Revision mode"
        }
    }

    static let defaultRevisionDetail = "60 seconds a question. The answer and explanation show as soon as you pick."

    static func defaultExamDetail(questions: Int) -> String {
        "One \(questions)-minute clock for the paper. Answers after you submit."
    }
}

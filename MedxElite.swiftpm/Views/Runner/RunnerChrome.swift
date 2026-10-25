import SwiftUI

// The runner's pieces that are not the question itself: the clock in the navigation bar, the
// time bar under it, the question navigator, the submit sheet, the block handover and the
// explanation. The bars are the platform's own; nothing here draws glass.

// MARK: - The clock

/// How much of the clock is left, in three steps, so the clock and the bar can change colour
/// without the runner re-evaluating on every second.
enum RunnerClockPhase: Equatable {
    case calm, low, critical

    static func of(remaining: Int, capacity: Int) -> RunnerClockPhase {
        guard capacity > 0 else { return .calm }
        let fraction = Double(remaining) / Double(capacity)
        if fraction <= 0.05 || remaining <= 10 { return .critical }
        if fraction <= 0.2 { return .low }
        return .calm
    }

    var color: Color {
        switch self {
        case .calm: return .primary
        case .low: return MedxOutcome.flagged
        case .critical: return MedxOutcome.wrong
        }
    }
}

/// The clock in the navigation bar. The system ticks it: a running clock is a
/// `Text(timerInterval:)` counting down to the deadline, so nothing in the runner redraws for
/// it, and a held clock (a revision answer shown) is the seconds that were left.
struct RunnerClock: View {
    let start: Date
    let deadline: Date
    /// Set while the clock is held, with the seconds that were left.
    let frozen: Int?
    let phase: RunnerClockPhase

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: frozen != nil ? "pause.circle.fill" : "timer")
                .font(.footnote.weight(.semibold))
            Group {
                if let frozen {
                    Text(MedxFormat.clock(frozen))
                } else {
                    Text(timerInterval: start...max(deadline, start), countsDown: true, showsHours: true)
                }
            }
            .font(.system(.subheadline, design: .rounded).weight(.bold))
            .monospacedDigit()
        }
        .foregroundStyle(phase.color)
        // The bar truncates the title before it may squeeze the clock: a long paper name was
        // leaving the clock as "1" or "…" beside its glyph.
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Time left")
    }
}

/// The thin bar under the navigation bar that drains with the clock.
struct RunnerTimeBar: View {
    let start: Date
    let deadline: Date
    let frozen: Int?
    let capacity: Int
    let phase: RunnerClockPhase

    var body: some View {
        Group {
            if let frozen {
                ProgressView(value: Double(frozen), total: Double(max(capacity, 1)))
            } else {
                ProgressView(timerInterval: start...max(deadline, start), countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
            }
        }
        .progressViewStyle(.linear)
        .tint(phase == .calm ? MedxTheme.accent : phase.color)
        .padding(.horizontal, MedxSpace.l)
        .padding(.top, MedxSpace.xs)
        .padding(.bottom, MedxSpace.s)
        .accessibilityHidden(true)
    }
}

// MARK: - Per-question status

enum RunnerQuestionStatus {
    case unanswered
    case answered
    case correct
    case wrong
    case timedOut

    /// The colour this state wears, or nil where the state is "nothing has happened here yet".
    var tint: Color? {
        switch self {
        case .unanswered: return nil
        case .answered: return MedxTheme.accent
        case .correct: return MedxOutcome.correct
        case .wrong: return MedxOutcome.wrong
        case .timedOut: return MedxOutcome.flagged
        }
    }

    var legendLabel: String {
        switch self {
        case .unanswered: return "Not answered"
        case .answered: return "Answered"
        case .correct: return "Correct"
        case .wrong: return "Wrong"
        case .timedOut: return "Timed out"
        }
    }
}

// MARK: - Outcome

enum RunnerOutcome: Equatable {
    case correct
    case incorrect
    case timedOut
    case unanswered

    init(response: QuestionResponse?) {
        guard let response else {
            self = .unanswered
            return
        }
        if response.timedOut == true {
            self = .timedOut
        } else if response.chosenId == nil {
            self = .unanswered
        } else {
            self = response.correct ? .correct : .incorrect
        }
    }

    var title: String {
        switch self {
        case .correct: return "Correct"
        case .incorrect: return "Incorrect"
        case .timedOut: return "Time up"
        case .unanswered: return "Not answered"
        }
    }

    var icon: String {
        switch self {
        case .correct: return "checkmark.circle.fill"
        case .incorrect: return "xmark.circle.fill"
        case .timedOut: return "clock.badge.exclamationmark.fill"
        case .unanswered: return "minus.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .correct: return MedxOutcome.correct
        case .incorrect: return MedxOutcome.wrong
        case .timedOut: return MedxOutcome.flagged
        case .unanswered: return MedxOutcome.pending
        }
    }
}

// MARK: - The navigator grid

/// Every question of the block as a numbered tile, coloured by its state. Shared by the
/// navigator sheet on a phone and the sidebar on an iPad in landscape.
struct RunnerNavigatorGrid: View {
    let range: Range<Int>
    let currentIndex: Int
    let furthestIndex: Int
    let statuses: [RunnerQuestionStatus]
    let marked: Set<Int>
    /// Revision reveals answers as you go, so jumping past the frontier is not allowed.
    let lockAhead: Bool
    let onSelect: (Int) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: MedxSpace.s)], spacing: MedxSpace.s) {
            ForEach(Array(range), id: \.self) { index in
                tile(for: index)
            }
        }
    }

    private func tile(for index: Int) -> some View {
        let status = statuses.indices.contains(index) ? statuses[index] : .unanswered
        let isCurrent = index == currentIndex
        let isLocked = lockAhead && index > furthestIndex
        let tint = status.tint

        return Button {
            onSelect(index)
        } label: {
            Text("\(index + 1)")
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(isCurrent ? Color.white : (tint ?? Color.primary))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(
                    isCurrent ? MedxTheme.accent : (tint?.opacity(0.18) ?? Color(uiColor: .tertiarySystemFill)),
                    in: RoundedRectangle(cornerRadius: MedxRadius.control, style: .continuous)
                )
                .overlay(alignment: .topTrailing) {
                    if marked.contains(index) {
                        Circle()
                            .fill(MedxOutcome.flagged)
                            .frame(width: 8, height: 8)
                            .padding(5)
                    }
                }
                .opacity(isLocked ? 0.35 : 1)
                .contentShape(RoundedRectangle(cornerRadius: MedxRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isLocked)
        .accessibilityLabel("Question \(index + 1)")
        .accessibilityValue(isCurrent ? "Current, \(status.legendLabel)" : status.legendLabel)
    }
}

/// The legend under a grid, as one wrapping row of chips.
struct RunnerNavigatorLegend: View {
    let lockAhead: Bool

    private var entries: [RunnerQuestionStatus] {
        lockAhead ? [.unanswered, .correct, .wrong, .timedOut] : [.unanswered, .answered]
    }

    var body: some View {
        HStack(spacing: MedxSpace.l) {
            ForEach(Array(entries.enumerated()), id: \.offset) { _, status in
                HStack(spacing: 6) {
                    Circle()
                        .fill(status.tint ?? Color(uiColor: .tertiarySystemFill))
                        .frame(width: 10, height: 10)
                    Text(status.legendLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 6) {
                Circle().fill(MedxOutcome.flagged).frame(width: 8, height: 8)
                Text("Bookmarked")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Question navigator sheet

struct QuestionNavigatorSheet: View {
    /// The questions this sheet may offer, absolute in the paper: a sectioned sitting passes
    /// only the block being sat, since a submitted block cannot be re-entered.
    let range: Range<Int>
    let currentIndex: Int
    let furthestIndex: Int
    let statuses: [RunnerQuestionStatus]
    let marked: Set<Int>
    let lockAhead: Bool
    let sectionLabel: String?
    let onSelect: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    private var counts: (answered: Int, open: Int, wrong: Int) {
        var answered = 0
        var open = 0
        var wrong = 0
        for index in range {
            let status = statuses.indices.contains(index) ? statuses[index] : .unanswered
            switch status {
            case .unanswered: open += 1
            case .wrong, .timedOut: answered += 1; wrong += 1
            default: answered += 1
            }
        }
        return (answered, open, wrong)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MedxSpace.xl) {
                    MedxStatRow {
                        MedxStatTile("\(counts.answered)", label: "answered", symbol: "checkmark.circle.fill", hue: MedxTheme.accent)
                        MedxStatTile("\(counts.open)", label: "left", symbol: "circle.dashed", hue: MedxOutcome.pending)
                        if lockAhead {
                            MedxStatTile("\(counts.wrong)", label: "wrong", symbol: "xmark.circle.fill", hue: MedxOutcome.wrong)
                        }
                    }

                    RunnerNavigatorGrid(
                        range: range,
                        currentIndex: currentIndex,
                        furthestIndex: furthestIndex,
                        statuses: statuses,
                        marked: marked,
                        lockAhead: lockAhead,
                        onSelect: onSelect
                    )

                    RunnerNavigatorLegend(lockAhead: lockAhead)
                }
                .padding(MedxSpace.l)
            }
            .navigationTitle(sectionLabel ?? "Questions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
    }
}

// MARK: - Submit confirmation

/// What is about to be handed in: answered, still open, flagged, the clock, and a way back to
/// the first open question before committing.
struct RunnerSubmitSheet: View {
    let answered: Int
    let unanswered: Int
    let flagged: Int
    /// Time left, for a timed paper.
    let clock: String?
    let title: String
    let detail: String
    let onReviewUnanswered: (() -> Void)?
    let onSubmit: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MedxSpace.xl) {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    MedxStatRow {
                        MedxStatTile("\(answered)", label: "answered", symbol: "checkmark.circle.fill", hue: MedxTheme.accent)
                        MedxStatTile("\(unanswered)", label: "unanswered", symbol: "circle.dashed", hue: unanswered > 0 ? MedxOutcome.wrong : MedxOutcome.pending)
                        MedxStatTile("\(flagged)", label: "bookmarked", symbol: "bookmark.fill", hue: flagged > 0 ? MedxOutcome.flagged : MedxOutcome.pending)
                        if let clock {
                            MedxStatTile(clock, label: "left", symbol: "timer", hue: MedxOutcome.pending)
                        }
                    }

                    VStack(spacing: MedxSpace.m) {
                        Button {
                            HapticManager.success()
                            onSubmit()
                        } label: {
                            Text("Submit")
                                .frame(maxWidth: .infinity)
                        }
                        .medxPrimary()

                        if unanswered > 0, let onReviewUnanswered {
                            Button {
                                HapticManager.light()
                                onReviewUnanswered()
                            } label: {
                                Text("Go to the first unanswered")
                                    .frame(maxWidth: .infinity)
                            }
                            .medxSecondary(size: .large)
                        }

                        Button("Keep going") { dismiss() }
                            .font(.subheadline.weight(.semibold))
                            .padding(.top, MedxSpace.xs)
                    }
                }
                .padding(MedxSpace.l)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Between blocks

/// What was just submitted and what is about to open.
struct MedxSectionHandover: Identifiable, Hashable {
    let closedLabel: String
    let score: Int
    let attempted: Int
    let total: Int
    let gradable: Bool
    let nextLabel: String
    let nextCount: Int
    let nextMinutes: Int
    let remainingSections: Int

    var id: String { closedLabel + "→" + nextLabel }
}

/// The acknowledgement between blocks, drawn *inside* the runner. It used to be a full-screen
/// cover, and presenting a cover over the runner fired the runner's `onDisappear`, which ended
/// the Live Activity — so a grand test had no Lock Screen clock from block two onward. The
/// next block's clock starts when the button is tapped, not while this is being read.
struct RunnerHandoverOverlay: View {
    let summary: MedxSectionHandover
    let onContinue: () -> Void

    private var fraction: Double {
        guard summary.total > 0 else { return 0 }
        return Double(summary.gradable ? summary.score : summary.attempted) / Double(summary.total)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MedxSpace.l) {
                Text("\(summary.closedLabel) submitted")
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)

                Text(summary.nextLabel)
                    .font(.largeTitle.weight(.bold))

                Text("\(summary.nextCount) questions, \(summary.nextMinutes) minutes. The block you just submitted is closed for good, and this one's clock starts when you tap below.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                MedxCard {
                    HStack(spacing: MedxSpace.l) {
                        MedxRing(fraction: fraction, tint: summary.gradable ? MedxOutcome.correct : MedxTheme.accent) {
                            VStack(spacing: 0) {
                                MedxFigure(summary.gradable ? "\(summary.score)" : "\(summary.attempted)")
                                Text("of \(summary.total)")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 88, height: 88)

                        MedxStatRow {
                            if summary.gradable {
                                MedxStatTile("\(summary.score)", label: "correct", symbol: "checkmark.circle.fill", hue: MedxOutcome.correct)
                            }
                            MedxStatTile("\(summary.attempted)", label: "attempted", symbol: "circle.fill", hue: MedxTheme.accent)
                            MedxStatTile("\(summary.remainingSections)", label: summary.remainingSections == 1 ? "block left" : "blocks left", symbol: "square.stack.fill", hue: MedxOutcome.pending)
                        }
                    }
                }

                if !summary.gradable {
                    Text("This paper came through without an answer key, so nothing here is scored; only what you attempted is recorded.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(MedxSpace.l)
            .padding(.top, MedxSpace.xl)
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                HapticManager.medium()
                onContinue()
            } label: {
                Text("Start \(summary.nextLabel)")
                    .frame(maxWidth: .infinity)
            }
            .medxPrimary()
            .padding(MedxSpace.l)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
    }
}

// MARK: - Explanation

/// The reveal under a revision answer, and the explanation on a review card: the outcome, the
/// right letter, the explanation and the reference.
struct RunnerExplanationCard: View {
    let question: Question
    let response: QuestionResponse?

    private var outcome: RunnerOutcome { RunnerOutcome(response: response) }

    private var correctLabel: String? {
        question.options.first { question.isCorrect(optionId: $0.id) }?.label
    }

    private var reference: String {
        question.reference?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var body: some View {
        MedxCard {
            VStack(alignment: .leading, spacing: MedxSpace.m) {
                HStack(spacing: MedxSpace.m) {
                    Image(systemName: outcome.icon)
                        .font(.title2)
                        .foregroundStyle(outcome.color)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(outcome.title)
                            .font(.headline)
                            .foregroundStyle(outcome.color)
                        if let correctLabel, !correctLabel.isEmpty {
                            Text(outcome == .correct ? "You picked \(correctLabel)" : "The answer is \(correctLabel)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 0)
                }

                Divider()

                Label("Explanation", systemImage: "lightbulb.fill")
                    .font(.subheadline.weight(.semibold))

                if let explanation = question.explanation, !explanation.isEmpty {
                    HTMLRichTextView(html: explanation, fontSize: 15, weight: .regular, textColor: .secondary)
                } else {
                    Text("No explanation came with this question.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if !reference.isEmpty {
                    Label(reference, systemImage: "book.closed")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: MedxRadius.card, style: .continuous)
                .strokeBorder(outcome.color.opacity(0.35), lineWidth: 1)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Figure and source tag

/// A tappable exported figure. Bare filenames are resolved against the image CDN, the same way
/// the ones inside the HTML are.
struct RunnerFigure: View {
    let raw: String

    var body: some View {
        if let url = MedxRichText.figureURL(raw) {
            Button {
                HapticManager.light()
                MedxImageZoom.present(url)
            } label: {
                CachedAsyncImage(url: url, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: MedxRadius.control, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Figure")
            .accessibilityHint("Opens the image full screen")
        }
    }
}

/// A small neutral chip naming where a question came from, truncating in the middle so both
/// the paper and the session stay readable ("FMGE…June 2023").
struct MedxSourceTag: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Label(text, systemImage: "doc.text")
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .truncationMode(.middle)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
            .frame(maxWidth: 220, alignment: .leading)
            .accessibilityLabel("From \(text)")
    }
}

import SwiftUI

// MARK: - The answer sheet
//
// The app's signature, and the one place the design spends boldness.
//
// Every exam this app prepares for is marked on an OMR sheet: a dense grid of numbered cells, each
// one filled or not. It is the single artifact from this subject that reads instantly, and it is far
// more informative than the progress bars it replaces — a bar says "62%", a sheet says *which*
// questions and where the damage is.
//
// It is not a new idea in this codebase, which is the argument for it. `RunnerProgressTrack` already
// drew exactly this for papers of 30 questions or fewer and then gave up and fell back to a gradient
// bar for anything longer. This promotes it from a fallback inside one HUD to the app's whole
// progress vocabulary, at four scales that are deliberately the same drawing:
//
//   sheet  a wrapped grid          Home's hero, the review after a sitting     one question
//   track  one row, current taller the runner's HUD                            one question
//   strip  one row, downsampled    a paper row, a module row                   a slice of an attempt
//   tick   a single cell           subject coverage, a duel round              one module / round
//
// **One `Canvas`, not N views.** 240 cells is one draw call and three batched paths — one per
// outcome colour. The fill-on animation advances a single `Double`, so a 240-cell sheet animating in
// costs the same as a 12-cell one. A `LazyVGrid` of 240 `RoundedRectangle`s, which is what this
// would be if built out of views, is 240 subtrees and was measurably the wrong answer.

/// What one cell of the sheet says.
public enum MedxSheetCell: Sendable, Hashable {
    /// Answered and right.
    case correct
    /// Answered and wrong.
    case wrong
    /// Answered, but nothing has scored it — an ungraded paper, or a question mid-sitting.
    case answered
    /// The clock ran out on it.
    case missed
    /// Not reached.
    case pending

    var color: Color {
        switch self {
        case .correct: return MedxDS.correct
        case .wrong: return MedxDS.wrong
        case .answered: return MedxTheme.accent
        case .missed: return MedxDS.warn
        case .pending: return MedxDS.pending
        }
    }

    /// Which outcome wins when several cells collapse into one at `strip` scale. A wrong answer is
    /// the thing worth surfacing, so severity beats frequency.
    var severity: Int {
        switch self {
        case .wrong: return 4
        case .missed: return 3
        case .answered: return 2
        case .correct: return 1
        case .pending: return 0
        }
    }
}

// MARK: - Scale

public enum MedxSheetScale: Sendable {
    /// A wrapped grid. Sizes itself from the width it is given, so it needs no `GeometryReader`.
    case sheet
    /// One row across the full width, the current cell drawn taller. The runner's HUD.
    case track
    /// A short fixed-width row, downsampled to eight cells. A list row's trailing indicator.
    case strip
    /// One cell.
    case tick

    /// Fixed at 24 for a sheet rather than derived from the available width. That is what lets the
    /// view state its own aspect ratio and skip a measuring pass — no `GeometryReader`, no
    /// `onGeometryChange`, no second layout pass on the one screen that draws 200 cells.
    func columns(for count: Int) -> Int {
        switch self {
        case .sheet: return 24
        case .track, .strip: return max(count, 1)
        case .tick: return 1
        }
    }

    /// The gap between cells, as a fraction of the pitch rather than as points.
    ///
    /// Additive spacing breaks down at both ends: on a 150-question track a fixed 2pt gap is wider
    /// than the cell it separates, and on a sheet it makes the height depend on the width in a way
    /// that defeats `aspectRatio`. A ratio holds at every count.
    var gapRatio: CGFloat {
        switch self {
        case .sheet: return 0.18
        case .track: return 0.28
        case .strip: return 0.25
        case .tick: return 0
        }
    }

    var radius: CGFloat {
        switch self {
        case .sheet: return 1.5
        case .track, .strip: return 2
        case .tick: return 2.5
        }
    }
}

// MARK: - The view

public struct MedxAnswerSheet: View {
    /// How many cells a `strip` collapses to. Eight is enough to read a shape at a glance and narrow
    /// enough to sit on the trailing edge of a list row without crowding the title.
    private static let stripCells = 8

    private let cells: [MedxSheetCell]
    private let scale: MedxSheetScale
    private let current: Int?
    private let label: String?

    @State private var reveal: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Real per-question data — the runner's track, the review sheet, Home's day.
    public init(
        cells: [MedxSheetCell],
        scale: MedxSheetScale = .sheet,
        current: Int? = nil,
        label: String? = nil
    ) {
        self.cells = cells
        self.scale = scale
        self.current = current
        self.label = label
    }

    /// A proportion, for the rows that only know a score out of a total.
    ///
    /// Most list rows are in this position: `MedxPaperRecord` carries `bestScore` and `total` and no
    /// per-question breakdown, because the catalogue is one document and the responses live on the
    /// attempt. Drawing eight cells of which `fraction` are filled says exactly what is known,
    /// without pretending to per-question detail the screen has not fetched.
    public init(fraction: Double, scale: MedxSheetScale = .strip, label: String? = nil) {
        let count = scale == .tick ? 1 : Self.stripCells
        let filled = Int((Double(count) * min(max(fraction, 0), 1)).rounded())
        self.cells = (0..<count).map { $0 < filled ? .correct : .pending }
        self.scale = scale
        self.current = nil
        self.label = label
    }

    // MARK: Body

    public var body: some View {
        sized
            .accessibilityElement()
            .accessibilityLabel(label ?? Self.describe(drawn))
            .onAppear {
                guard reveal == 0 else { return }
                guard !reduceMotion else {
                    reveal = 1
                    return
                }
                withAnimation(MedxDS.settle) { reveal = 1 }
            }
    }

    /// Each scale states its own size, so none of them needs to be measured first.
    @ViewBuilder
    private var sized: some View {
        switch scale {
        case .sheet:
            // Exact, not approximate: with a gap expressed as a fraction of the pitch, height is
            // `rows × pitch` and pitch is `width / 24`, so the ratio is independent of the width.
            canvas.aspectRatio(CGFloat(24) / CGFloat(max(rows, 1)), contentMode: .fit)
        case .track:
            canvas.frame(height: 7)
        case .strip:
            canvas.frame(width: 46, height: 7)
        case .tick:
            canvas.frame(width: 8, height: 8)
        }
    }

    private var canvas: some View {
        Canvas { context, size in
            draw(in: context, size: size)
        }
    }
}

// MARK: - Drawing

private extension MedxAnswerSheet {

    /// The cells actually drawn. `strip` collapses whatever it was given into eight buckets, taking
    /// the most severe outcome in each — a wrong answer inside a bucket is the thing worth seeing, so
    /// severity beats frequency.
    var drawn: [MedxSheetCell] {
        switch scale {
        case .sheet, .track:
            return cells
        case .tick:
            return [cells.first ?? .pending]
        case .strip:
            guard cells.count > MedxAnswerSheet.stripCells else { return cells }
            let size = Double(cells.count) / Double(MedxAnswerSheet.stripCells)
            return (0..<MedxAnswerSheet.stripCells).map { bucket in
                let lower = Int(Double(bucket) * size)
                let upper = max(lower + 1, Int(Double(bucket + 1) * size))
                return cells[lower..<min(upper, cells.count)]
                    .max { $0.severity < $1.severity } ?? .pending
            }
        }
    }

    var rows: Int {
        let columns = scale.columns(for: drawn.count)
        guard columns > 0 else { return 1 }
        return max(Int((Double(drawn.count) / Double(columns)).rounded(.up)), 1)
    }

    /// One path per outcome, filled once each — so a 240-cell sheet is at most five fills rather than
    /// 240 draws, and adding a cell costs nothing.
    func draw(in context: GraphicsContext, size: CGSize) {
        let list = drawn
        guard !list.isEmpty, size.width > 0 else { return }

        let columns = scale.columns(for: list.count)
        let pitch = size.width / CGFloat(columns)
        let side = pitch * (1 - scale.gapRatio)
        guard side > 0.3 else { return }

        // Vertical pitch is the horizontal one for a sheet (square cells); for a single row the
        // cells simply fill the height they were given.
        let cellHeight = scale == .sheet ? side : size.height
        let revealed = Int((Double(list.count) * min(max(reveal, 0), 1)).rounded())

        var paths: [MedxSheetCell: Path] = [:]
        var currentRect: CGRect?

        for (index, cell) in list.enumerated() {
            let column = index % columns
            let row = index / columns
            let rect = CGRect(
                x: CGFloat(column) * pitch,
                y: scale == .sheet ? CGFloat(row) * pitch : 0,
                width: side,
                height: cellHeight
            )

            if index == current {
                currentRect = rect
                continue
            }

            let resolved = index < revealed ? cell : .pending
            paths[resolved, default: Path()].addRoundedRect(
                in: rect,
                cornerSize: CGSize(width: scale.radius, height: scale.radius),
                style: .continuous
            )
        }

        for (cell, path) in paths {
            context.fill(path, with: .color(cell.color))
        }

        // Drawn last and wider, so the question you are on is findable without reading a number.
        if let currentRect {
            let grown = currentRect.insetBy(dx: -pitch * scale.gapRatio * 0.5, dy: 0)
            context.fill(
                Path(roundedRect: grown, cornerSize: CGSize(width: scale.radius, height: scale.radius), style: .continuous),
                with: .color(MedxTheme.accent)
            )
        }
    }

    /// One sentence for VoiceOver, because a grid of 200 cells cannot be read cell by cell.
    static func describe(_ cells: [MedxSheetCell]) -> String {
        var counts: [MedxSheetCell: Int] = [:]
        for cell in cells { counts[cell, default: 0] += 1 }

        let order: [(MedxSheetCell, String)] = [
            (.correct, "correct"),
            (.wrong, "wrong"),
            (.answered, "answered"),
            (.missed, "timed out"),
            (.pending, "not reached"),
        ]
        let parts = order.compactMap { cell, word -> String? in
            guard let count = counts[cell], count > 0 else { return nil }
            return "\(count) \(word)"
        }
        return parts.isEmpty ? "Nothing answered yet" : parts.joined(separator: ", ")
    }
}

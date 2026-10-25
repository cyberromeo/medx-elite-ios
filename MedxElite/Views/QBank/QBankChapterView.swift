import SwiftUI

/// Chapters and modules for one subject, in either bank. Every chapter is a section and every
/// module a row, so the shape of a 247-module subject is the shape of the page — and the list
/// only builds the rows that are on screen.
public struct QBankChapterView: View {
    public let subject: MedxBankSubject
    public let practisedModuleIds: Set<String>
    public let attempts: [SittingAttempt]
    public var onStartModule: (QBankModuleSummary, SittingMode) -> Void

    @State private var selectedModuleForStart: QBankModuleSummary?
    /// The pick made inside the mode sheet, started once the sheet has gone — see
    /// `StartSessionSheet` for why not sooner.
    @State private var pendingStart: (module: QBankModuleSummary, mode: SittingMode)?
    @State private var searchText = ""

    /// Sittings per module, keyed by module id — folded once here rather than on every `body`.
    private let moduleResults: [String: ModuleRecord]

    private struct ModuleRecord {
        var count: Int
        var best: Int
        var total: Int
    }

    public init(
        subject: MedxBankSubject,
        practisedModuleIds: Set<String> = [],
        attempts: [SittingAttempt],
        onStartModule: @escaping (QBankModuleSummary, SittingMode) -> Void
    ) {
        self.subject = subject
        self.practisedModuleIds = practisedModuleIds
        self.attempts = attempts
        self.onStartModule = onStartModule

        var map: [String: ModuleRecord] = [:]
        for attempt in attempts where attempt.kind == "qbank" {
            var record = map[attempt.sourceId] ?? ModuleRecord(count: 0, best: 0, total: attempt.total)
            record.count += 1
            record.best = max(record.best, attempt.score)
            record.total = max(record.total, attempt.total)
            map[attempt.sourceId] = record
        }
        moduleResults = map
    }

    private var chapters: [MedxBankChapter] {
        subject.chapters
    }

    private var practisedCount: Int {
        let ids = Set(subject.modules.map(\.id))
        return ids.intersection(practisedModuleIds).count
    }

    private var matchingChapters: [MedxBankChapter] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return chapters }
        return chapters.compactMap { chapter in
            let modules = chapter.modules.filter {
                $0.name.localizedCaseInsensitiveContains(query)
            }
            guard !modules.isEmpty || chapter.name.localizedCaseInsensitiveContains(query) else {
                return nil
            }
            return MedxBankChapter(id: chapter.id, name: chapter.name, modules: modules)
        }
    }

    public var body: some View {
        List {
            Section {
                summary
            }

            if matchingChapters.isEmpty {
                Section {
                    MedxEmptyState(
                        searchText.isEmpty ? "No modules yet" : "No matches",
                        symbol: searchText.isEmpty ? "tray" : "magnifyingglass",
                        message: searchText.isEmpty
                            ? "This subject has no modules yet."
                            : "No module matches “\(searchText)”."
                    )
                }
            } else {
                ForEach(matchingChapters) { chapter in
                    Section {
                        ForEach(chapter.modules) { module in
                            moduleRow(module)
                        }
                    } header: {
                        Text(chapter.name.isEmpty ? "Modules" : chapter.name)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(subject.name)
        .navigationSubtitle("\(subject.moduleCount) modules · \(MedxFormat.count(subject.questionCount)) questions")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Search modules")
        .sheet(item: $selectedModuleForStart, onDismiss: startPending) { module in
            StartSessionSheet(
                title: module.name,
                subtitle: subject.name,
                questionCount: module.questionCount
            ) { mode in
                pendingStart = (module: module, mode: mode)
            }
        }
    }

    private func startPending() {
        guard let pending = pendingStart else { return }
        pendingStart = nil
        onStartModule(pending.module, pending.mode)
    }

    // MARK: - Summary

    private var summary: some View {
        HStack(spacing: MedxSpace.l) {
            MedxRing(
                fraction: Double(practisedCount) / Double(max(subject.moduleCount, 1)),
                tint: MedxOutcome.correct
            ) {
                VStack(spacing: 0) {
                    MedxFigure("\(practisedCount)", style: .title3)
                    Text("done")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 72, height: 72)

            VStack(alignment: .leading, spacing: MedxSpace.xs) {
                Text("\(MedxFormat.ratio(practisedCount, of: subject.moduleCount)) modules practised")
                    .font(.headline)
                Text("\(chapters.count) chapters · \(MedxFormat.count(subject.questionCount)) questions")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(subject.bank.eyebrow)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, MedxSpace.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(subject.name)
        .accessibilityValue("\(practisedCount) of \(subject.moduleCount) modules practised")
    }

    // MARK: - Module

    private func moduleRow(_ module: QBankModuleSummary) -> some View {
        let record = moduleResults[module.id]

        return Button {
            HapticManager.light()
            selectedModuleForStart = module
        } label: {
            HStack(spacing: MedxSpace.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(module.name)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Text(detail(for: module, record: record))
                        .font(.footnote)
                        .foregroundStyle(record == nil ? Color.secondary : MedxOutcome.correct)
                }

                Spacer(minLength: MedxSpace.s)

                Image(systemName: record == nil ? "play.circle.fill" : "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(record == nil ? MedxTheme.accent : MedxOutcome.correct)
            }
            .padding(.vertical, 2)
            .foregroundStyle(Color.primary)
        }
        // Long press to skip the mode sheet — the two modes are the whole decision.
        .contextMenu {
            Button {
                HapticManager.medium()
                onStartModule(module, .revision)
            } label: {
                Label("Revision mode", systemImage: "bolt")
            }
            Button {
                HapticManager.medium()
                onStartModule(module, .exam)
            } label: {
                Label("Exam mode", systemImage: "timer")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(module.name)
        .accessibilityValue(detail(for: module, record: record))
        .accessibilityHint("Opens the mode picker")
    }

    private func detail(for module: QBankModuleSummary, record: ModuleRecord?) -> String {
        guard let record else { return "\(module.questionCount) questions" }
        let sittings = record.count == 1 ? "1 sitting" : "\(record.count) sittings"
        return "\(module.questionCount) questions · best \(record.best) of \(record.total) · \(sittings)"
    }
}

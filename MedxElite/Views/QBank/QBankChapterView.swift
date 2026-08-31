import SwiftUI

/// Chapters and modules for one subject, in either bank. Chapters collapse, so a 247-module
/// subject does not build 247 rows before the first frame.
public struct QBankChapterView: View {
    public let subject: MedxBankSubject
    public let practisedModuleIds: Set<String>
    public let attempts: [SittingAttempt]
    public var onStartModule: (QBankModuleSummary, SittingMode) -> Void

    @State private var selectedModuleForStart: QBankModuleSummary?
    @State private var expandedChapters: Set<String> = []
    @State private var searchText = ""

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
    }

    private var chapters: [MedxBankChapter] {
        subject.chapters
    }

    /// Best score per module, keyed by module id.
    private var moduleResults: [String: (count: Int, best: Int, total: Int)] {
        var map: [String: (count: Int, best: Int, total: Int)] = [:]
        for attempt in attempts where attempt.kind == "qbank" {
            let current = map[attempt.sourceId] ?? (count: 0, best: 0, total: attempt.total)
            map[attempt.sourceId] = (
                count: current.count + 1,
                best: max(current.best, attempt.score),
                total: max(current.total, attempt.total)
            )
        }
        return map
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
            heroSection

            if matchingChapters.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No Modules", systemImage: searchText.isEmpty ? "tray" : "magnifyingglass")
                    } description: {
                        Text(searchText.isEmpty
                             ? "This subject has no modules yet."
                             : "No module matches “\(searchText)”.")
                    }
                    .medxPlainRow()
                }
            } else {
                // A `Section` per chapter, so collapsing is the header's job and a 247-module subject
                // still only builds the rows on screen. The hand-built disclosure card this replaces was
                // a `Button` wrapping a card wrapping a rotating chevron.
                ForEach(matchingChapters) { chapter in
                    Section(isExpanded: expandedBinding(for: chapter)) {
                        ForEach(chapter.modules) { module in
                            moduleRow(module)
                        }
                    } header: {
                        MedxHeader(chapter.name, count: chapter.modules.count)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .medxPage()
        .navigationTitle(subject.name)
        .navigationBarTitleDisplayMode(.large)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: "Search modules"
        )
        .sheet(item: $selectedModuleForStart) { module in
            StartSessionSheet(
                title: module.name,
                subtitle: subject.name,
                questionCount: module.questionCount
            ) { mode in
                onStartModule(module, mode)
            }
        }
        .onAppear {
            // Open the first chapter so the screen is never just a stack of closed rows.
            if expandedChapters.isEmpty, let first = chapters.first {
                expandedChapters.insert(first.id)
            }
        }
    }

    /// A search result is always open — hiding a match behind a collapsed header is the one thing a
    /// filtered list must never do.
    private func expandedBinding(for chapter: MedxBankChapter) -> Binding<Bool> {
        Binding(
            get: { expandedChapters.contains(chapter.id) || !searchText.isEmpty },
            set: { open in
                guard searchText.isEmpty else { return }
                HapticManager.light()
                if open {
                    expandedChapters.insert(chapter.id)
                } else {
                    expandedChapters.remove(chapter.id)
                }
            }
        )
    }

    // MARK: - Hero

    private var heroSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text(subject.questionCount.formatted())
                    .font(MedxType.display)
                    .contentTransition(.numericText())

                Text("\(subject.bank.label) · \(subject.moduleCount) modules · \(practisedCount) practised")
                    .medxTag()

                MedxAnswerSheet(
                    fraction: Double(practisedCount) / Double(max(subject.moduleCount, 1)),
                    scale: .sheet,
                    label: "\(practisedCount) of \(subject.moduleCount) modules practised"
                )
            }
            .medxPlainRow()
        }
    }

    // MARK: - Module

    private func moduleRow(_ module: QBankModuleSummary) -> some View {
        let result = moduleResults[module.id]

        return Button {
            HapticManager.light()
            selectedModuleForStart = module
        } label: {
            MedxRow(
                lead: "\(module.questionCount)",
                title: module.name,
                tag: result.map { "\($0.count) sitting\($0.count == 1 ? "" : "s")" },
                detail: result.map { "best \($0.best)/\($0.total)" } ?? "not attempted"
            ) {
                if let result {
                    MedxAnswerSheet(
                        fraction: Double(result.best) / Double(max(result.total, 1)),
                        label: "best \(result.best) of \(result.total)"
                    )
                } else {
                    EmptyView()
                }
            }
        }
        .buttonStyle(.plain)
        .medxListRow()
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
        .accessibilityValue(result == nil
                            ? "\(module.questionCount) questions, not attempted"
                            : "\(module.questionCount) questions, best \(result?.best ?? 0) of \(result?.total ?? 0)")
        .accessibilityHint("Opens the mode picker")
    }
}

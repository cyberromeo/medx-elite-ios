import SwiftUI

/// Chapters and modules for one subject. Chapters collapse, so a 200-module subject does
/// not build 200 rows before the first frame.
public struct QBankChapterView: View {
    public let subject: QBankSubject
    public let practisedModuleIds: Set<String>
    public let attempts: [SittingAttempt]
    public var onStartModule: (QBankModuleSummary, SittingMode) -> Void

    @State private var selectedModuleForStart: QBankModuleSummary?
    @State private var expandedChapters: Set<Int> = []
    @State private var searchText = ""

    public init(
        subject: QBankSubject,
        practisedModuleIds: Set<String> = [],
        attempts: [SittingAttempt],
        onStartModule: @escaping (QBankModuleSummary, SittingMode) -> Void
    ) {
        self.subject = subject
        self.practisedModuleIds = practisedModuleIds
        self.attempts = attempts
        self.onStartModule = onStartModule
    }

    private var chapters: [QBankChapter] {
        subject.chapters ?? []
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
        let ids = Set(chapters.flatMap { ($0.modules ?? []).map(\.id) })
        return ids.intersection(practisedModuleIds).count
    }

    private var matchingChapters: [QBankChapter] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return chapters }
        return chapters.compactMap { chapter in
            let modules = (chapter.modules ?? []).filter {
                $0.name.localizedCaseInsensitiveContains(query)
            }
            guard !modules.isEmpty || chapter.name.localizedCaseInsensitiveContains(query) else {
                return nil
            }
            return QBankChapter(id: chapter.id, name: chapter.name, modules: modules)
        }
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                summaryCard

                if matchingChapters.isEmpty {
                    ContentUnavailableView {
                        Label("No Modules", systemImage: "magnifyingglass")
                    } description: {
                        Text(searchText.isEmpty
                             ? "This subject has no modules yet."
                             : "No module matches “\(searchText)”.")
                    }
                    .padding(.top, 32)
                } else {
                    ForEach(matchingChapters) { chapter in
                        chapterSection(chapter)
                    }
                }
            }
            .padding(.horizontal, MedxSurface.gutter)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(MedxSurface.groupedBackground.ignoresSafeArea())
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

    // MARK: - Summary

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("\(subject.moduleCount) modules", systemImage: "square.grid.2x2.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(practisedCount) practised")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ProgressView(
                value: Double(practisedCount),
                total: Double(max(subject.moduleCount, 1))
            )
            .tint(MedxTheme.successGreen)

            Text("\((subject.questionCount ?? 0).formatted()) questions available")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .medxCard()
    }

    // MARK: - Chapter

    private func chapterSection(_ chapter: QBankChapter) -> some View {
        let isExpanded = expandedChapters.contains(chapter.id) || !searchText.isEmpty
        let modules = chapter.modules ?? []

        return VStack(alignment: .leading, spacing: 8) {
            Button {
                HapticManager.light()
                withAnimation(.easeOut(duration: 0.2)) {
                    if expandedChapters.contains(chapter.id) {
                        expandedChapters.remove(chapter.id)
                    } else {
                        expandedChapters.insert(chapter.id)
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Text(chapter.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 8)

                    Text("\(modules.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .medxCard(cornerRadius: 12)
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!searchText.isEmpty)
            .accessibilityLabel(chapter.name)
            .accessibilityValue("\(modules.count) modules, \(isExpanded ? "expanded" : "collapsed")")

            if isExpanded {
                VStack(spacing: 8) {
                    ForEach(modules) { module in
                        moduleRow(module)
                    }
                }
                .padding(.leading, 8)
            }
        }
    }

    // MARK: - Module

    private func moduleRow(_ module: QBankModuleSummary) -> some View {
        let result = moduleResults[module.id]

        return Button {
            HapticManager.light()
            selectedModuleForStart = module
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(module.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)

                    if let result {
                        Text("\(module.questionCount) questions · best \(result.best)/\(result.total) · \(result.count) sitting\(result.count == 1 ? "" : "s")")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(MedxTheme.successGreen)
                    } else {
                        Text("\(module.questionCount) questions")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: result == nil ? "play.circle.fill" : "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(result == nil ? Color.accentColor : MedxTheme.successGreen)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: 60)
            .medxTile()
            .contentShape(RoundedRectangle(cornerRadius: MedxSurface.tileRadius, style: .continuous))
        }
        .buttonStyle(BouncyButtonStyle())
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
        .accessibilityValue(result == nil
                            ? "\(module.questionCount) questions, not attempted"
                            : "\(module.questionCount) questions, best \(result?.best ?? 0) of \(result?.total ?? 0)")
        .accessibilityHint("Opens the mode picker")
    }
}

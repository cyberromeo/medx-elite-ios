import SwiftUI

/// Builds a sitting to order: pick the subjects, narrow the scope, choose a length and a
/// mode, and the questions are assembled from whatever source can supply them.
///
/// There are three sources, tried in this order, because each is cheaper than the next:
/// bookmarks (already whole `Question` values on device), the question index (needs one
/// module fetch per distinct module), and finally random module sampling (used when nothing
/// is indexed yet, so the feature works on a fresh install).
public struct MedxCustomModuleSheet: View {
    @ObservedObject private var index = MedxQuestionIndexStore.shared
    @ObservedObject private var activityStore = ActivityStore.shared
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var medxTheme = MedxAccentThemeStore.shared

    @State private var subjects: [MedxBankSubject] = []
    @State private var selectedSubjectIds: Set<String> = []
    @State private var filters = MedxQuestionFilters()
    @State private var length = 20
    @State private var mode: SittingMode = .revision
    @State private var history = MedxAnswerHistory()
    @State private var isLoading = true
    @State private var isBuilding = false
    @State private var buildFailed = false

    @Environment(\.dismiss) private var dismiss

    public init() {}

    private static let lengths = [10, 20, 40, 60, 100]

    private var uid: String? { authService.currentSession?.uid }

    private var chosenSubjects: [MedxBankSubject] {
        selectedSubjectIds.isEmpty ? subjects : subjects.filter { selectedSubjectIds.contains($0.id) }
    }

    private var subjectSummary: String {
        switch selectedSubjectIds.count {
        case 0: return "All subjects"
        case 1: return subjects.first { selectedSubjectIds.contains($0.id) }?.name ?? "1 subject"
        default: return "\(selectedSubjectIds.count) subjects"
        }
    }

    /// How many questions the app can actually supply, when it can tell.
    private var availableCount: Int? {
        if filters.bookmarkedOnly {
            return bookmarkPool.count
        }
        guard !index.isEmpty else { return nil }
        return index.pool(subjectKeys: selectedSubjectIds, filters: filters, history: history).count
    }

    private var bookmarkPool: [BookmarkedQuestion] {
        activityStore.bookmarks(for: uid).filter { bookmark in
            let subjectOK = selectedSubjectIds.isEmpty
                || chosenSubjects.contains { $0.name.caseInsensitiveCompare(bookmark.subject) == .orderedSame }
            let imageOK = !filters.imageBased || MedxIndexedQuestion.hasFigure(bookmark.question)
            return subjectOK && imageOK
        }
    }

    public var body: some View {
        NavigationStack {
            Form {
                subjectSection
                scopeSection
                shapeSection
                availabilitySection
            }
            .scrollContentBackground(.hidden)
            .medxPage(.qbank)
            .navigationTitle("Custom module")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                startBar
            }
            .alert("Couldn't build that sitting", isPresented: $buildFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Nothing matched those choices. Try a wider scope, or build the question index in Settings so the whole bank is available.")
            }
            .task { await load() }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Sections

    private var subjectSection: some View {
        Section {
            NavigationLink {
                MedxSubjectMultiPicker(subjects: subjects, selection: $selectedSubjectIds)
            } label: {
                HStack {
                    Label("Subjects", systemImage: "books.vertical")
                    Spacer()
                    Text(subjectSummary)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(minHeight: 44)
            }
        } footer: {
            Text("Leave it on all subjects for a mixed paper.")
        }
    }

    private var scopeSection: some View {
        Section("Scope") {
            Picker("Status", selection: $filters.status) {
                ForEach(MedxQuestionFilters.Status.allCases) { status in
                    Text(status.label).tag(status)
                }
            }
            .pickerStyle(.menu)

            Toggle(isOn: $filters.imageBased) {
                Label("Image-based only", systemImage: "photo")
            }

            Toggle(isOn: $filters.bookmarkedOnly) {
                Label("Bookmarked only", systemImage: "bookmark")
            }
        }
        .tint(MedxTheme.accent)
    }

    private var shapeSection: some View {
        Section("Sitting") {
            Picker("Questions", selection: $length) {
                ForEach(Self.lengths, id: \.self) { value in
                    Text("\(value)").tag(value)
                }
            }
            .pickerStyle(.segmented)

            Picker("Mode", selection: $mode) {
                Text("Revision").tag(SittingMode.revision)
                Text("Exam").tag(SittingMode.exam)
            }
            .pickerStyle(.segmented)

            Text(mode == .exam
                 ? "\(length) minutes total, graded at the end."
                 : "60 seconds per question, answer revealed as you go.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var availabilitySection: some View {
        Section {
            if let availableCount {
                HStack {
                    Label("Matching questions", systemImage: "number")
                    Spacer()
                    Text("\(availableCount.formatted())")
                        .font(.body.monospacedDigit())
                        .foregroundStyle(availableCount >= length ? MedxTheme.successGreen : MedxTheme.warningOrange)
                        .contentTransition(.numericText())
                }
                .frame(minHeight: 44)
            } else {
                Label("Sampled from your subjects", systemImage: "dice")
                    .frame(minHeight: 44)
            }
        } footer: {
            if availableCount == nil {
                Text("The question index has not been built, so questions are sampled from a handful of modules instead. Build it in Settings to filter across the whole bank.")
            } else if let availableCount, availableCount < length {
                Text("Only \(availableCount) match — the sitting will be that long.")
            }
        }
    }

    private var startBar: some View {
        Button {
            build()
        } label: {
            HStack(spacing: 8) {
                if isBuilding {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                    Text("Assembling…")
                } else {
                    Image(systemName: "play.fill")
                    Text("Start sitting")
                }
            }
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 50)
        }
        .medxFilledButton()
        .buttonBorderShape(.capsule)
        .tint(MedxTheme.accent)
        .disabled(isLoading || isBuilding)
        .medxFloatingBar()
    }

    // MARK: - Building

    private func build() {
        guard !isBuilding else { return }
        isBuilding = true
        HapticManager.medium()

        Task {
            let questions = await assemble()
            isBuilding = false

            guard !questions.isEmpty else {
                HapticManager.error()
                buildFailed = true
                return
            }

            appState.startSitting(
                RunnerPayload(
                    kind: "qbank",
                    id: "custom-" + String(UUID().uuidString.prefix(8)),
                    name: sittingName,
                    subject: selectedSubjectIds.count == 1 ? subjectSummary : "Custom",
                    mode: mode,
                    gradable: true,
                    questions: questions
                )
            )
        }
    }

    private var sittingName: String {
        var parts: [String] = []
        if filters.bookmarkedOnly { parts.append("Bookmarked") }
        if filters.status != .any { parts.append(filters.status.label) }
        if filters.imageBased { parts.append("image-based") }
        parts.append(subjectSummary.lowercased())
        return "Custom · " + parts.joined(separator: ", ")
    }

    private func assemble() async -> [Question] {
        // 1. Bookmarks are already complete questions on this device.
        if filters.bookmarkedOnly {
            return Array(bookmarkPool.map(\.question).shuffled().prefix(length))
        }

        // 2. The index knows exactly which questions qualify; one fetch per module.
        let pool = index.pool(subjectKeys: selectedSubjectIds, filters: filters, history: history)
        if !pool.isEmpty {
            return await index.questions(for: pool.shuffled(), limit: length)
        }

        // 3. Nothing indexed: sample modules at random so the feature still works.
        return await sampleFromModules()
    }

    /// Capped at twelve module fetches: a custom sitting should not turn into a hundred
    /// Firestore reads because a filter happened to be narrow.
    private func sampleFromModules() async -> [Question] {
        guard let token = try? await authService.getValidIdToken() else { return [] }

        var candidates: [QBankModuleSummary] = []
        for subject in chosenSubjects {
            for chapter in subject.chapters {
                candidates.append(contentsOf: chapter.modules.filter { $0.questionCount > 0 })
            }
        }
        candidates.shuffle()

        var collected: [Question] = []
        var fetches = 0

        for module in candidates {
            if Task.isCancelled || collected.count >= length || fetches >= 12 { break }
            fetches += 1

            guard let detail = try? await FirestoreService.shared.fetchQBankModule(
                moduleId: module.id,
                idToken: token
            ) else { continue }

            var questions = detail.questions ?? []
            if filters.imageBased {
                questions = questions.filter { MedxIndexedQuestion.hasFigure($0) }
            }
            // The module is known here, so the composite `moduleId#questionId` is available and
            // exact — worth using, because 2,405 question ids exist in both banks. The plain set
            // still counts behind it, since it is the only record of a question met in an earlier
            // custom or search sitting, whose module nothing wrote down.
            func attempted(_ question: Question) -> Bool {
                history.attemptedKeys.contains("\(module.id)#\(question.id)")
                    || history.attempted.contains(question.id)
            }
            switch filters.status {
            case .any:
                break
            case .attempted:
                questions = questions.filter(attempted)
            case .unattempted:
                questions = questions.filter { !attempted($0) }
            case .wrong:
                questions = questions.filter {
                    history.wrongKeys.contains("\(module.id)#\($0.id)") || history.wrong.contains($0.id)
                }
            }

            collected.append(contentsOf: questions.shuffled())
        }

        return Array(collected.shuffled().prefix(length))
    }

    // MARK: - Data

    private func load() async {
        defer { isLoading = false }
        guard let uid else { return }
        guard let token = try? await authService.getValidIdToken() else { return }

        async let subjectsTask = FirestoreService.shared.fetchQBankBanks(idToken: token)
        async let attemptsTask = FirestoreService.shared.fetchUserAttempts(uid: uid, idToken: token)

        subjects = (try? await subjectsTask) ?? []
        history = MedxAnswerHistory(
            attempts: (try? await attemptsTask) ?? [],
            bookmarks: activityStore.bookmarks(for: uid)
        )
    }
}

// MARK: - Subject picker

struct MedxSubjectMultiPicker: View {
    let subjects: [MedxBankSubject]
    @Binding var selection: Set<String>

    /// Grouped by bank, because both banks have an Anatomy and one flat list of forty subjects
    /// with two of several names is unusable.
    private var groups: [(bank: MedxBank, subjects: [MedxBankSubject])] {
        MedxBank.allCases.compactMap { bank in
            let matching = subjects.filter { $0.bank == bank }
            return matching.isEmpty ? nil : (bank, matching)
        }
    }

    var body: some View {
        List {
            Section {
                Button {
                    HapticManager.selection()
                    selection.removeAll()
                } label: {
                    HStack {
                        Text("All subjects")
                            .foregroundStyle(.primary)
                        Spacer()
                        if selection.isEmpty {
                            Image(systemName: "checkmark")
                                .foregroundStyle(MedxTheme.accent)
                        }
                    }
                    .frame(minHeight: 44)
                }
            }

            ForEach(groups, id: \.bank) { group in
                Section {
                    ForEach(group.subjects) { subject in
                        Button {
                            HapticManager.selection()
                            if selection.contains(subject.id) {
                                selection.remove(subject.id)
                            } else {
                                selection.insert(subject.id)
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(subject.name)
                                        .foregroundStyle(.primary)
                                    Text("\(subject.questionCount.formatted()) questions")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selection.contains(subject.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(MedxTheme.accent)
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                            .frame(minHeight: 44)
                        }
                    }
                } header: {
                    Text(group.bank.label)
                }
            }
        }
        .animation(.snappy(duration: 0.18), value: selection)
        .scrollContentBackground(.hidden)
        .medxPage(.qbank)
        .navigationTitle("Subjects")
        .navigationBarTitleDisplayMode(.inline)
    }
}

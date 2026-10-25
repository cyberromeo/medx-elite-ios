import SwiftUI

/// Quick sitting: a sitting built to order. Pick the subjects, narrow the scope, choose a length
/// and a mode, and the questions are assembled from whatever source can supply them.
///
/// There are three sources, tried in this order, because each is cheaper than the next:
/// bookmarks (already whole `Question` values on device), the question index (needs one
/// module fetch per distinct module), and finally random module sampling (used when nothing
/// is indexed yet, so the feature works on a fresh install).
///
/// A sheet rather than a push: it is a builder that ends in a sitting, and `AppState.startSitting`
/// waits for the sheet to go before the runner comes up.
public struct MedxCustomModuleSheet: View {
    @ObservedObject private var index = MedxQuestionIndexStore.shared
    @ObservedObject private var activityStore = ActivityStore.shared
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var appState = AppState.shared

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
            List {
                subjectSection
                scopeSection
                shapeSection
                availabilitySection
            }
            .listStyle(.insetGrouped)
            .navigationTitle(MedxFeature.quickSitting.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isBuilding {
                        ProgressView()
                    } else {
                        Button("Start") { build() }
                            .buttonStyle(.glassProminent)
                            .disabled(isLoading)
                    }
                }
            }
            .alert("Couldn't build that sitting", isPresented: $buildFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Nothing matched those choices. Try a wider scope, or set up offline search so the whole bank is available.")
            }
            .task { await load() }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationSizing(.page)
    }

    // MARK: - Sections

    private var subjectSection: some View {
        Section {
            NavigationLink {
                MedxSubjectMultiPicker(subjects: subjects, selection: $selectedSubjectIds)
            } label: {
                LabeledContent {
                    Text(subjectSummary)
                        .lineLimit(1)
                } label: {
                    Label("Subjects", systemImage: MedxFeature.qbank.symbol)
                }
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
    }

    private var shapeSection: some View {
        Section {
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
        } header: {
            Text("Sitting")
        } footer: {
            Text(mode == .exam
                 ? "One \(length)-minute clock, answers after you submit."
                 : "60 seconds a question, the answer shown as you go.")
        }
    }

    @ViewBuilder
    private var availabilitySection: some View {
        Section {
            if let availableCount {
                LabeledContent {
                    Text(MedxFormat.count(availableCount))
                        .monospacedDigit()
                        .foregroundStyle(availableCount >= length ? MedxOutcome.correct : MedxOutcome.flagged)
                        .contentTransition(.numericText())
                } label: {
                    Label("Matching questions", systemImage: "number")
                }
            } else {
                Label("Sampled from your subjects", systemImage: MedxFeature.quickSitting.symbol)
            }
        } footer: {
            if availableCount == nil {
                Text("Offline search is not set up yet, so questions come from a handful of modules. Set it up from Library ▸ Search questions to pick from the whole bank.")
            } else if let availableCount, availableCount < length {
                Text("Only \(availableCount) match, so the sitting will be that long.")
            }
        }
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
                    // One id per set of choices, so a sitting left half-way with the same choices
                    // is offered back instead of a fresh random id orphaning its saved sitting.
                    id: "quick-" + MedxStableHash.of(choicesKey),
                    name: sittingName,
                    subject: selectedSubjectIds.count == 1 ? subjectSummary : "Custom",
                    mode: mode,
                    gradable: true,
                    questions: questions
                )
            )
        }
    }

    private var choicesKey: String {
        [
            selectedSubjectIds.sorted().joined(separator: "+"),
            filters.status.rawValue,
            filters.imageBased ? "img" : "-",
            filters.bookmarkedOnly ? "bm" : "-",
            String(length),
            mode.rawValue
        ].joined(separator: "#")
    }

    private var sittingName: String {
        var parts: [String] = []
        if filters.bookmarkedOnly { parts.append("Bookmarked") }
        if filters.status != .any { parts.append(filters.status.label) }
        if filters.imageBased { parts.append("image-based") }
        parts.append(subjectSummary.lowercased())
        return "Quick · " + parts.joined(separator: ", ")
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

    /// Capped at twelve module fetches: a quick sitting should not turn into a hundred
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
                                    Text("\(MedxFormat.count(subject.questionCount)) questions")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selection.contains(subject.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(MedxTheme.accent)
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                        }
                    }
                } header: {
                    Text(group.bank.label)
                }
            }
        }
        .listStyle(.insetGrouped)
        .animation(.snappy(duration: 0.18), value: selection)
        .navigationTitle("Subjects")
        .navigationBarTitleDisplayMode(.inline)
    }
}

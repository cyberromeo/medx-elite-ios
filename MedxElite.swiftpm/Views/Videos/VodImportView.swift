import SwiftUI
import UIKit

/// File a raw bucket recording into the curated Classes library.
///
/// The native port of the PWA's admin `VodBrowser`: browse `medx_vod`, preview a recording to see
/// what it is, then add it to whichever batch → subject is chosen at the top. The bucket has no
/// usable titles, so each import is auto-numbered "{subject} — Class N" from the highest number
/// already in that subject — the number you would have typed anyway. An imported class then reads
/// in the Classes tab exactly like an original ARISE one.
public struct VodImportView: View {
    @ObservedObject private var authService = AuthService.shared

    // Destination tree
    @State private var folders: [MedxLibraryFolder] = []
    @State private var selectedFolderId: String?
    @State private var selectedSubjectId: String?
    @State private var structureState: MedxLoadState = .loading

    // What is already filed, so a recording that has a home is marked.
    @State private var filedSubjectById: [String: String] = [:]

    // The bucket, paged.
    @State private var items: [MedxVodItem] = []
    @State private var cursor: String?
    @State private var isDone = false
    @State private var isLoading = true
    @State private var failure: String?
    @State private var query = ""
    @State private var folderKey = ""
    @State private var onlyCC = false
    @State private var autoPages = 0
    @State private var playing: RecordedVideo?

    // Imported in this session, so numbering and the filed mark keep up before a reload.
    @State private var sessionAdded: Set<String> = []
    @State private var sessionTitlesBySubject: [String: [String]] = [:]
    @State private var adding: String?

    public init() {}

    private static let pageSize = 48
    private static let autoPageLimit = 3

    // MARK: - Derived

    private var selectedFolder: MedxLibraryFolder? {
        folders.first { $0.id == selectedFolderId }
    }

    private var selectedSubject: MedxLibrarySubject? {
        selectedFolder?.subjects.first { $0.id == selectedSubjectId }
    }

    private var ready: Bool { selectedFolder != nil && selectedSubject != nil }

    /// The next class number for the chosen subject — existing titles plus this session's adds.
    private var nextNumber: Int {
        guard let subject = selectedSubject else { return 1 }
        let titles = subject.titles + (sessionTitlesBySubject[subject.id] ?? [])
        return MedxVideoLibraryStore.nextClassNumber(existingTitles: titles)
    }

    private var shown: [MedxVodItem] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.filter { item in
            if onlyCC, !item.hasSubtitles { return false }
            guard !needle.isEmpty else { return true }
            return item.display.title.localizedCaseInsensitiveContains(needle)
                || item.rawKey.localizedCaseInsensitiveContains(needle)
                || item.folder.localizedCaseInsensitiveContains(needle)
        }
    }

    /// Where a recording already lives, or `nil` if it has no home yet.
    private func filedSubject(for item: MedxVodItem) -> String? {
        let classId = MedxVideoLibraryStore.classIdFor(item.id)
        if let name = filedSubjectById[classId] { return name }
        if sessionAdded.contains(classId) { return selectedSubject?.name }
        return nil
    }

    private var subtitle: String {
        guard ready, let folder = selectedFolder, let subject = selectedSubject else {
            return "Pick a batch and a subject"
        }
        return "Filing into \(folder.name) · \(subject.name)"
    }

    // MARK: - Body

    public var body: some View {
        List {
            destinationSection
            folderSection

            if let failure {
                Section {
                    HStack(spacing: MedxSpace.m) {
                        Label(failure, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: MedxSpace.s)
                        Button("Dismiss") { self.failure = nil }
                            .medxSecondary(size: .small)
                    }
                }
            }

            if isLoading, items.isEmpty {
                Section {
                    MedxPlaceholderRows(count: 8)
                }
            } else if shown.isEmpty {
                Section {
                    MedxEmptyState(
                        "Nothing loaded matches",
                        symbol: "magnifyingglass",
                        message: "Load more, clear the filter, or find a recording by its exact folder code."
                    )
                }
            } else {
                Section {
                    ForEach(shown) { item in
                        row(item)
                    }
                } header: {
                    Text("Bucket · \(MedxFormat.count(shown.count))")
                } footer: {
                    Text("Tap a recording to preview it. Add files it into the batch and subject above.")
                }
            }

            pagingSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(MedxFeature.importClasses.title)
        .navigationSubtitle(subtitle)
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $query, prompt: "Filter by key, folder or name")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Toggle(isOn: $onlyCC) {
                    Label("Subtitled only", systemImage: "captions.bubble")
                }
                .toggleStyle(.button)
                .accessibilityLabel("Only recordings with subtitles")
            }
        }
        .refreshable { await reload() }
        .task {
            if case .loading = structureState { await loadStructure() }
            if items.isEmpty { await loadMore(auto: false) }
        }
        .onChange(of: selectedFolderId) { _, _ in
            selectedSubjectId = selectedFolder?.subjects.first?.id
        }
        .fullScreenCover(item: $playing) { video in
            VideoPlayerView(video: video) { playing = nil }
        }
    }

    // MARK: - Destination

    private var destinationSection: some View {
        Section {
            switch structureState {
            case .loading:
                HStack(spacing: MedxSpace.s) {
                    ProgressView().controlSize(.small)
                    Text("Loading the library structure…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            case .failed(let message):
                HStack(spacing: MedxSpace.m) {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: MedxSpace.s)
                    Button("Retry") { Task { await loadStructure() } }
                        .medxSecondary(size: .small)
                }
            case .loaded:
                Picker("Batch", selection: $selectedFolderId) {
                    ForEach(folders) { folder in
                        Text(folder.name).tag(Optional(folder.id))
                    }
                }
                .pickerStyle(.menu)

                Picker("Subject", selection: $selectedSubjectId) {
                    ForEach(selectedFolder?.subjects ?? []) { subject in
                        Text(subject.name).tag(Optional(subject.id))
                    }
                }
                .pickerStyle(.menu)
                .disabled(selectedFolder?.subjects.isEmpty ?? true)
            }
        } header: {
            Text("Filing into")
        } footer: {
            if ready {
                Text("The next add files “\(selectedSubject?.name ?? "") — Class \(nextNumber)”.")
            }
        }
    }

    // MARK: - Folder code

    private var folderSection: some View {
        Section {
            HStack(spacing: MedxSpace.m) {
                TextField("Exact folder code", text: $folderKey)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.go)
                    .onSubmit { Task { await fetchByFolderKey() } }

                Button("Fetch") { Task { await fetchByFolderKey() } }
                    .medxSecondary(size: .small)
                    .disabled(folderKey.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Find by folder code")
        } footer: {
            // The bucket has no text index, so the search field only reaches what is paged in.
            // `folder` is indexed, which makes an exact folder code the one search that reaches
            // all ~2,900.
            Text("The search field only reaches what is loaded. A folder code reaches the whole bucket.")
        }
    }

    // MARK: - Row

    private func row(_ item: MedxVodItem) -> some View {
        let label = item.display
        let video = item.asRecordedVideo
        let filedIn = filedSubject(for: item)
        let isAdding = adding == item.id
        let playable = !item.streamUrl.isEmpty

        return HStack(spacing: MedxSpace.m) {
            Button {
                guard playable else {
                    HapticManager.error()
                    return
                }
                HapticManager.light()
                playing = video
            } label: {
                HStack(spacing: MedxSpace.m) {
                    MedxSymbolTile(
                        filedIn == nil ? "play.circle.fill" : "checkmark",
                        hue: filedIn == nil ? MedxFeature.vod.color : MedxOutcome.correct,
                        size: 36
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(label.title)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(detailLine(item, label: label))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if let filedIn {
                            Text("Filed in \(filedIn)")
                                .font(.footnote)
                                .foregroundStyle(MedxOutcome.correct)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!playable)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(label.title)

            if filedIn == nil {
                Button {
                    Task { await add(item) }
                } label: {
                    if isAdding {
                        ProgressView()
                    } else {
                        Text("Add")
                    }
                }
                .medxPrimary(size: .small)
                .disabled(!ready || isAdding || !playable)
                .accessibilityLabel(ready ? "Add to \(selectedSubject?.name ?? "")" : "Pick a subject first")
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            if playable {
                Button {
                    HapticManager.light()
                    playing = video
                } label: {
                    Label("Play", systemImage: "play.circle")
                }
            }
            Button {
                UIPasteboard.general.string = item.rawKey
            } label: {
                Label("Copy file key", systemImage: "doc.on.doc")
            }
        }
    }

    private func detailLine(_ item: MedxVodItem, label: (title: String, sub: String, opaque: Bool)) -> String {
        var parts: [String] = []
        if !label.sub.isEmpty { parts.append(label.sub) }
        if !item.formattedDuration.isEmpty { parts.append(item.formattedDuration) }
        if item.hasSubtitles { parts.append("Subtitled") }
        if item.streamUrl.isEmpty { parts.append("No stream") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Paging

    @ViewBuilder
    private var pagingSection: some View {
        if !items.isEmpty {
            Section {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if !isDone {
                    Button {
                        HapticManager.light()
                        Task { await loadMore(auto: false) }
                    } label: {
                        Label("Older uploads", systemImage: "arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .onAppear {
                        guard autoPages < Self.autoPageLimit, query.isEmpty else { return }
                        Task { await loadMore(auto: true) }
                    }
                } else {
                    Text("That is everything, \(MedxFormat.count(items.count)) recordings.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: - Data

    private func loadStructure() async {
        structureState = .loading
        guard let token = try? await authService.getValidIdToken() else {
            structureState = .failed("Sign in again to read the library.")
            return
        }
        do {
            async let foldersTask = MedxVideoLibraryStore.shared.listStructure(idToken: token)
            async let classesTask = FirestoreService.shared.fetchVideos(idToken: token)
            let (loadedFolders, classes) = try await (foldersTask, classesTask)
            folders = loadedFolders
            filedSubjectById = Dictionary(classes.map { ($0.id, $0.subject) }, uniquingKeysWith: { first, _ in first })
            if selectedFolderId == nil {
                selectedFolderId = folders.first?.id
                selectedSubjectId = folders.first?.subjects.first?.id
            }
            structureState = .loaded
        } catch {
            structureState = .failed("Couldn't load the library. Check your connection.")
        }
    }

    private func reload() async {
        cursor = nil
        isDone = false
        autoPages = 0
        items = []
        await loadMore(auto: false)
    }

    private func loadMore(auto: Bool) async {
        guard !isDone else { return }
        isLoading = true
        failure = nil
        defer { isLoading = false }

        guard let token = try? await authService.getValidIdToken() else {
            failure = "Sign in again to load recordings."
            return
        }
        do {
            let page = try await FirestoreService.shared.fetchVodPage(
                pageSize: Self.pageSize, cursor: cursor, idToken: token
            )
            let seen = Set(items.map(\.id))
            items.append(contentsOf: page.items.filter { !seen.contains($0.id) })
            cursor = page.cursor
            isDone = page.done
            if auto { autoPages += 1 }
        } catch {
            failure = "That page did not load. Check your connection and try again."
        }
    }

    private func fetchByFolderKey() async {
        let key = folderKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        isLoading = true
        failure = nil
        defer { isLoading = false }
        guard let token = try? await authService.getValidIdToken() else {
            failure = "Sign in again to load recordings."
            return
        }
        do {
            let found = try await FirestoreService.shared.fetchVodByFolder(key: key, idToken: token)
            let seen = Set(items.map(\.id))
            items.insert(contentsOf: found.filter { !seen.contains($0.id) }, at: 0)
            query = key
        } catch {
            failure = "Couldn't fetch that folder code."
        }
    }

    private func add(_ item: MedxVodItem) async {
        // One at a time: two quick taps used to file two recordings under the same class number.
        guard adding == nil else { return }
        guard let folder = selectedFolder, let subject = selectedSubject else { return }
        guard let token = try? await authService.getValidIdToken() else {
            failure = "Sign in again to file recordings."
            return
        }
        adding = item.id
        defer { adding = nil }
        let title = "\(subject.name) — Class \(nextNumber)"
        do {
            let record = try await MedxVideoLibraryStore.shared.importOne(
                vod: item, folder: folder, subject: subject, title: title, idToken: token
            )
            if let docId = record["id"] as? String {
                sessionAdded.insert(docId)
                filedSubjectById[docId] = subject.name
            }
            sessionTitlesBySubject[subject.id, default: []].append(title)
            HapticManager.success()
        } catch {
            HapticManager.error()
            failure = "Couldn't file that recording. Check your connection and try again."
        }
    }
}

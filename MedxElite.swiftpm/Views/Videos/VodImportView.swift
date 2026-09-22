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

    // What is already filed, so a recording that has a home is greyed out.
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

    // Imported in this session, so numbering and the filed badge keep up before a reload.
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

    // MARK: - Body

    public var body: some View {
        List {
            Section {
                header
                    .medxCardRow(vertical: 5)
                destinationCard
                    .medxCardRow(vertical: 5)
                tools
                    .medxCardRow(vertical: 5)
                if let failure {
                    errorNote(failure)
                        .medxCardRow(vertical: 5)
                }
            }

            Section {
                ForEach(shown) { item in
                    row(item)
                        .medxCardRow(vertical: 5)
                }
            } header: {
                if !shown.isEmpty {
                    MedxRuleHeader("Bucket", count: shown.count)
                        .textCase(nil)
                        .listRowInsets(
                            EdgeInsets(top: 6, leading: MedxSurface.gutter, bottom: 6, trailing: MedxSurface.gutter)
                        )
                }
            }

            Section {
                VStack(spacing: 12) { footer }
                    .medxCardRow(vertical: 8)
            }
        }
        .medxCardList()
        .navigationTitle("Import to Classes")
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await reload() }
        .task {
            if case .loading = structureState { await loadStructure() }
            if items.isEmpty { await loadMore(auto: false) }
        }
        .fullScreenCover(item: $playing) { video in
            VideoPlayerView(video: video) { playing = nil }
        }
    }

    // MARK: - Header

    private var header: some View {
        MedxPageHeader(
            section: .videos,
            eyebrow: "ARISE · file into the library",
            lead: "Preview a recording from the raw bucket, then add it to a batch and subject. "
                + "It appears in Classes numbered automatically."
        )
    }

    // MARK: - Destination picker

    private var destinationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Filing into")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(ready ? "\(selectedFolder?.name ?? "") · \(selectedSubject?.name ?? "")" : "Pick a batch and subject")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(ready ? .primary : .secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                MedxSymbolMark("tray.and.arrow.down.fill", hue: MedxCandy.violet, size: 40)
            }

            switch structureState {
            case .loading:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading the library structure…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .failed(let message):
                HStack(spacing: 8) {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Button("Retry") { Task { await loadStructure() } }
                        .font(.caption.weight(.semibold))
                }
            case .loaded:
                HStack(spacing: 8) {
                    batchMenu
                    subjectMenu
                }
                if ready {
                    Text("Next add files “\(selectedSubject?.name ?? "") — Class \(nextNumber)”.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .medxCard()
    }

    private var batchMenu: some View {
        Menu {
            ForEach(folders) { folder in
                Button {
                    HapticManager.selection()
                    selectedFolderId = folder.id
                    selectedSubjectId = folder.subjects.first?.id
                } label: {
                    Label(folder.name, systemImage: folder.id == selectedFolderId ? "checkmark" : "folder")
                }
            }
        } label: {
            pickerLabel(icon: "folder.fill", text: selectedFolder?.name ?? "Batch")
        }
    }

    private var subjectMenu: some View {
        Menu {
            if let folder = selectedFolder, !folder.subjects.isEmpty {
                ForEach(folder.subjects) { subject in
                    Button {
                        HapticManager.selection()
                        selectedSubjectId = subject.id
                    } label: {
                        Label(subject.name, systemImage: subject.id == selectedSubjectId ? "checkmark" : "square.stack")
                    }
                }
            } else {
                Text("No subjects in this batch")
            }
        } label: {
            pickerLabel(icon: "square.stack.3d.up.fill", text: selectedSubject?.name ?? "Subject")
        }
        .disabled(selectedFolder?.subjects.isEmpty ?? true)
    }

    private func pickerLabel(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(MedxCandy.onSoft(MedxCandy.violet))
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .frame(maxWidth: .infinity)
        .background(MedxCandy.violetSoft, in: Capsule())
    }

    // MARK: - Tools

    private var tools: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("Filter loaded — key, folder or name", text: $query)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.search)
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear filter")
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(MedxSurface.fieldFill, in: Capsule())

                Button {
                    HapticManager.selection()
                    onlyCC.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "captions.bubble").font(.caption.weight(.bold))
                        Text("CC").font(.caption.weight(.bold))
                    }
                    .foregroundStyle(onlyCC ? MedxCandy.onSoft(MedxCandy.blue) : .secondary)
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .background(onlyCC ? MedxCandy.blueSoft : MedxSurface.fieldFill, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Only recordings with subtitles")
            }

            // The bucket has no text index, so a filter only reaches what is paged in. `folder`
            // is indexed, which makes an exact folder code the one search that reaches all ~2,900.
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "number")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("Fetch a bucket folder by exact code", text: $folderKey)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.go)
                        .onSubmit { Task { await fetchByFolderKey() } }
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(MedxSurface.fieldFill, in: Capsule())

                Button("Fetch") { Task { await fetchByFolderKey() } }
                    .font(.subheadline.weight(.semibold))
                    .disabled(folderKey.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: - Row

    private func row(_ item: MedxVodItem) -> some View {
        let label = item.display
        let video = item.asRecordedVideo
        let filedIn = filedSubject(for: item)
        let isAdding = adding == item.id

        return HStack(spacing: 8) {
            Button {
                guard !item.streamUrl.isEmpty else { HapticManager.error(); return }
                HapticManager.light()
                playing = video
            } label: {
                HStack(spacing: 12) {
                    MedxSymbolMark(
                        filedIn == nil ? "play.circle.fill" : "checkmark",
                        hue: filedIn == nil ? MedxCandy.blue : MedxTheme.successGreen,
                        size: 36
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(label.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text([label.sub, item.formattedDuration, item.streamUrl.isEmpty ? "no stream" : nil]
                            .compactMap { $0 }
                            .filter { !$0.isEmpty }
                            .joined(separator: " · "))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if item.hasSubtitles {
                        Image(systemName: "captions.bubble")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(item.streamUrl.isEmpty)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(label.title)

            addControl(item, filedIn: filedIn, isAdding: isAdding)
        }
        .padding(12)
        .frame(minHeight: 58)
        .medxCard()
        .contextMenu {
            if !item.streamUrl.isEmpty {
                Button {
                    HapticManager.light()
                    playing = video
                } label: { Label("Play", systemImage: "play.circle") }
            }
            Button {
                UIPasteboard.general.string = item.rawKey
            } label: { Label("Copy file key", systemImage: "doc.on.doc") }
        }
    }

    @ViewBuilder
    private func addControl(_ item: MedxVodItem, filedIn: String?, isAdding: Bool) -> some View {
        if let filedIn {
            HStack(spacing: 4) {
                Image(systemName: "checkmark").font(.caption2.weight(.black))
                Text(filedIn).font(.caption2.weight(.semibold)).lineLimit(1)
            }
            .foregroundStyle(MedxTheme.successGreen)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(MedxTheme.successGreen.opacity(0.14), in: Capsule())
            .accessibilityLabel("Already filed in \(filedIn)")
        } else {
            Button {
                Task { await add(item) }
            } label: {
                HStack(spacing: 4) {
                    if isAdding {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "plus").font(.caption.weight(.black))
                    }
                    Text("Add").font(.caption.weight(.bold))
                }
                .foregroundStyle(ready && !item.streamUrl.isEmpty ? MedxCandy.onSoft(MedxCandy.violet) : Color.secondary)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(
                    (ready && !item.streamUrl.isEmpty ? MedxCandy.violetSoft : MedxSurface.fieldFill),
                    in: Capsule()
                )
            }
            .buttonStyle(.plain)
            .disabled(!ready || isAdding || item.streamUrl.isEmpty)
            .accessibilityLabel(ready ? "Add to \(selectedSubject?.name ?? "")" : "Pick a subject first")
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        if isLoading {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 20)
        } else if shown.isEmpty {
            ContentUnavailableView {
                Label("Nothing loaded matches", systemImage: "magnifyingglass")
            } description: {
                Text("Load another page, clear the filter, or fetch a bucket folder by its exact code.")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }

        if !isDone, !isLoading {
            Color.clear
                .frame(height: 1)
                .onAppear {
                    guard autoPages < Self.autoPageLimit, query.isEmpty else { return }
                    Task { await loadMore(auto: true) }
                }
            Button {
                HapticManager.light()
                Task { await loadMore(auto: false) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down").font(.footnote.weight(.bold))
                    Text("Older uploads").font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .medxBorderedButton()
            .buttonBorderShape(.capsule)
        }
    }

    private func errorNote(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(MedxTheme.warningOrange)
            Text(message).font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button("Dismiss") { failure = nil }
                .font(.caption.weight(.semibold))
        }
        .padding(12)
        .medxCard()
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
            failure = "Sign in again to read the bucket."
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
            failure = "Sign in again to read the bucket."
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

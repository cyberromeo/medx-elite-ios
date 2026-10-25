import SwiftUI

/// Image decks, one card at a time, nothing scored. A grid rather than a list: these decks are
/// pure artwork, so a thumbnail says more about a subject than any row could.
public struct FlashcardsSubjectListView: View {
    @ObservedObject private var authService = AuthService.shared

    @State private var subjects: [FlashcardSubject] = []
    @State private var searchText = ""
    @State private var loadState: MedxLoadState = .loading
    #if DEBUG
    @State private var debugPick: FlashcardSubject?
    #endif

    public init() {}

    private var filteredSubjects: [FlashcardSubject] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return subjects }
        return subjects.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var totalCards: Int {
        subjects.reduce(0) { $0 + $1.cardCount }
    }

    private var isLoading: Bool { loadState == .loading && subjects.isEmpty }

    private var subtitle: String {
        guard !subjects.isEmpty else { return "Image decks, nothing scored" }
        return "\(MedxFormat.count(totalCards)) cards · \(subjects.count) subjects"
    }

    public var body: some View {
        FlashcardLayoutReader { layout in
            Group {
                if case .failed(let message) = loadState, subjects.isEmpty {
                    MedxEmptyState(
                        "Couldn't load flashcards",
                        symbol: "wifi.exclamationmark",
                        message: message,
                        actionTitle: "Try again"
                    ) {
                        HapticManager.light()
                        loadState = .loading
                        Task { await loadFlashcards() }
                    }
                } else if loadState == .loaded, subjects.isEmpty {
                    MedxEmptyState(
                        "No flashcards yet",
                        symbol: MedxFeature.flashcards.symbol,
                        message: "Flashcard subjects appear here once they are published."
                    )
                } else {
                    grid(layout: layout)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
        }
        .navigationTitle(MedxFeature.flashcards.title)
        .navigationSubtitle(subtitle)
        .navigationBarTitleDisplayMode(.large)
        #if DEBUG
        // Screenshot runs only (`-medxScreen deck`): opens the first subject once loaded.
        .navigationDestination(item: $debugPick) { item in
            FlashcardStudyView(subject: item)
        }
        .onChange(of: subjects.count) { _, count in
            guard count > 0, debugPick == nil,
                  UserDefaults.standard.string(forKey: "medxScreen") == "deck" else { return }
            debugPick = subjects.first
        }
        #endif
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                FlashcardArtworkMenu {
                    Image(systemName: "rectangle.on.rectangle.angled")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                MedxProfileButton()
            }
        }
        .searchable(text: $searchText, prompt: "Search flashcards")
        .task {
            guard case .loading = loadState else { return }
            await medxLoadRevalidating { await loadFlashcards() }
        }
    }

    // MARK: - Grid

    private func grid(layout: FlashcardLayout) -> some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 158, maximum: 260), spacing: MedxSpace.m)],
                spacing: MedxSpace.m
            ) {
                if isLoading {
                    ForEach(0..<6, id: \.self) { _ in
                        placeholderTile
                    }
                } else {
                    ForEach(filteredSubjects) { subject in
                        NavigationLink {
                            FlashcardStudyView(subject: subject)
                        } label: {
                            subjectTile(subject, layout: layout)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(subject.name)
                        .accessibilityValue("\(subject.cardCount) cards")
                    }
                }
            }
            .padding(.horizontal, MedxSpace.l)
            .padding(.vertical, MedxSpace.m)

            if !isLoading, filteredSubjects.isEmpty {
                MedxEmptyState(
                    "No matches",
                    symbol: "magnifyingglass",
                    message: "No subject matches “\(searchText)”."
                )
            }
        }
        .refreshable {
            // A pull always reaches the backend: cached copies are kept for offline, never
            // served in place of a fresh read the student asked for.
            await CacheManager.shared.markAllStale()
            await loadFlashcards()
        }
        .onReceive(NotificationCenter.default.publisher(for: .medxContentShouldRefresh)) { _ in
            Task { await loadFlashcards() }
        }
    }

    private func subjectTile(_ subject: FlashcardSubject, layout: FlashcardLayout) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Color.clear
                    .aspectRatio(4.0 / 3.0, contentMode: .fit)
                    .overlay {
                        if let preview = previewURL(for: subject, layout: layout) {
                            CachedAsyncImage(url: preview, contentMode: .fill, maxPixelSize: 700)
                        } else {
                            Color(uiColor: .tertiarySystemFill)
                                .overlay {
                                    Image(systemName: MedxSubjectArt.symbol(for: subject.name))
                                        .font(.largeTitle)
                                        .foregroundStyle(.secondary)
                                }
                        }
                    }
                    .clipped()

                Text("\(subject.cardCount)")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.55), in: Capsule())
                    .padding(MedxSpace.s)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(subject.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(subject.cardCount == 1 ? "1 card" : "\(subject.cardCount) cards")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MedxSpace.m)
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: MedxRadius.card, style: .continuous))
    }

    private var placeholderTile: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color(uiColor: .tertiarySystemFill)
                .aspectRatio(4.0 / 3.0, contentMode: .fit)

            VStack(alignment: .leading, spacing: 2) {
                Text("A subject name")
                    .font(.subheadline.weight(.semibold))
                Text("24 cards")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MedxSpace.m)
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: MedxRadius.card, style: .continuous))
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }

    private func previewURL(for subject: FlashcardSubject, layout: FlashcardLayout) -> URL? {
        for card in subject.cards ?? [] {
            if let raw = card.variants?.url(for: layout), let url = URL(string: raw) {
                return url
            }
        }
        return nil
    }

    // MARK: - Data

    private func loadFlashcards() async {
        do {
            let token = try await authService.getValidIdToken()
            subjects = try await FirestoreService.shared.fetchFlashcardSubjects(idToken: token)
            loadState = .loaded
        } catch {
            loadState = subjects.isEmpty
                ? .failed("Check your connection and try again.")
                : .loaded
        }
    }
}

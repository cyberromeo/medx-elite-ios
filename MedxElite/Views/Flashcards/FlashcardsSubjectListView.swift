import SwiftUI

public struct FlashcardsSubjectListView: View {
    @ObservedObject private var authService = AuthService.shared

    @State private var subjects: [FlashcardSubject] = []
    @State private var searchText = ""
    @State private var loadState: MedxLoadState = .loading

    public init() {}

    private var filteredSubjects: [FlashcardSubject] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return subjects }
        return subjects.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var totalCards: Int {
        subjects.reduce(0) { $0 + $1.cardCount }
    }

    public var body: some View {
        FlashcardLayoutReader { layout in
            Group {
                switch loadState {
                case .loading:
                    ProgressView("Loading flashcards…")
                        .controlSize(.large)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed(let message):
                    ContentUnavailableView {
                        Label("Couldn't Load Flashcards", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Try Again") {
                            HapticManager.light()
                            loadState = .loading
                            Task { await loadFlashcards() }
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                    }
                case .loaded:
                    if subjects.isEmpty {
                        ContentUnavailableView(
                            "No Flashcards",
                            systemImage: "rectangle.stack.badge.minus",
                            description: Text("Flashcard subjects will appear here when available.")
                        )
                    } else {
                        content(layout: layout)
                    }
                }
            }
            .background(MedxSurface.groupedBackground.ignoresSafeArea())
        }
        .navigationTitle("Flashcards")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                FlashcardArtworkMenu {
                    Image(systemName: "rectangle.on.rectangle.angled")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                ProfileSettingsButton()
            }
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: "Search flashcards"
        )
        .task {
            guard case .loading = loadState else { return }
            await loadFlashcards()
        }
    }

    private func content(layout: FlashcardLayout) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                MedxMetricsRow {
                    MedxMetric(
                        icon: "rectangle.stack.fill",
                        value: totalCards.formatted(),
                        label: "cards",
                        color: MedxTheme.indigoAccent
                    )
                    MedxMetric(
                        icon: "books.vertical.fill",
                        value: "\(subjects.count)",
                        label: "subjects",
                        color: MedxTheme.cyanAccent
                    )
                }

                if filteredSubjects.isEmpty {
                    ContentUnavailableView {
                        Label("No Matches", systemImage: "magnifyingglass")
                    } description: {
                        Text("No subject matches “\(searchText)”.")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 32)
                } else {
                    subjectGrid(layout: layout)
                }
            }
            .padding(.horizontal, MedxSurface.gutter)
            .padding(.top, 6)
            .padding(.bottom, 28)
        }
        .refreshable {
            await loadFlashcards()
        }
    }

    /// Two-up cards with a real preview: these decks are pure artwork, so a thumbnail says
    /// more about a subject than any icon can.
    private func subjectGrid(layout: FlashcardLayout) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 158, maximum: 260), spacing: 12)],
            spacing: 12
        ) {
            ForEach(filteredSubjects) { subject in
                NavigationLink {
                    FlashcardStudyView(subject: subject)
                } label: {
                    subjectCard(subject, layout: layout)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(subject.name)
                .accessibilityValue("\(subject.cardCount) cards")
            }
        }
    }

    private func subjectCard(_ subject: FlashcardSubject, layout: FlashcardLayout) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Color.clear
                    .aspectRatio(4.0 / 3.0, contentMode: .fit)
                    .overlay {
                        if let preview = previewURL(for: subject, layout: layout) {
                            CachedAsyncImage(url: preview, contentMode: .fill, maxPixelSize: 700)
                        } else {
                            MedxSurface.tileFill
                                .overlay(
                                    Image(systemName: "sparkles.rectangle.stack.fill")
                                        .font(.system(size: 22, weight: .semibold))
                                        .foregroundStyle(MedxTheme.indigoAccent)
                                )
                        }
                    }
                    .clipped()

                Text("\(subject.cardCount)")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.5), in: Capsule())
                    .padding(10)
            }
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: MedxSurface.cardRadius,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: MedxSurface.cardRadius,
                    style: .continuous
                )
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(subject.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(subject.cardCount == 1 ? "1 visual card" : "\(subject.cardCount) visual cards")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
        }
        .medxCard()
    }

    private func previewURL(for subject: FlashcardSubject, layout: FlashcardLayout) -> URL? {
        for card in subject.cards ?? [] {
            if let raw = card.variants?.url(for: layout), let url = URL(string: raw) {
                return url
            }
        }
        return nil
    }

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

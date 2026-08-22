import SwiftUI

public struct FlashcardsSubjectListView: View {
    @ObservedObject var authService = AuthService.shared
    @State private var subjects: [FlashcardSubject] = []
    @State private var searchText = ""
    @State private var isLoading = true

    public init() {}

    private var filteredSubjects: [FlashcardSubject] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return subjects
        }
        return subjects.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var totalCards: Int {
        subjects.reduce(0) { $0 + $1.cardCount }
    }

    public var body: some View {
        FlashcardLayoutReader { layout in
            ZStack {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()

                if isLoading {
                    ProgressView("Loading Flashcards…")
                        .controlSize(.large)
                } else if subjects.isEmpty {
                    ContentUnavailableView(
                        "No Flashcards",
                        systemImage: "rectangle.stack.badge.minus",
                        description: Text("Flashcard subjects will appear here when available.")
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
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
                            .padding(.horizontal, 20)
                            .padding(.top, 6)

                            if filteredSubjects.isEmpty {
                                ContentUnavailableView {
                                    Label("No Subjects", systemImage: "magnifyingglass")
                                } description: {
                                    Text("Try a different search.")
                                }
                                .padding(.top, 36)
                            } else {
                                subjectGrid(layout: layout)
                            }
                        }
                        .padding(.bottom, 28)
                    }
                    .refreshable {
                        await loadFlashcards()
                    }
                }
            }
        }
        .navigationTitle("Flashcards")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ProfileSettingsButton()
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search flashcards")
        .task {
            await loadFlashcards()
        }
    }

    // MARK: - Grid

    /// Two-up cards with a real preview: these decks are pure artwork, so a thumbnail
    /// says more about a subject than any icon can.
    private func subjectGrid(layout: FlashcardLayout) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 158, maximum: 260), spacing: 14)],
            spacing: 14
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
        .padding(.horizontal, 20)
    }

    private func subjectCard(_ subject: FlashcardSubject, layout: FlashcardLayout) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Color.clear
                    .aspectRatio(4.0 / 3.0, contentMode: .fit)
                    .overlay {
                        if let preview = previewURL(for: subject, layout: layout) {
                            CachedAsyncImage(url: preview, contentMode: .fill)
                        } else {
                            LinearGradient(
                                colors: [
                                    MedxTheme.indigoAccent.opacity(0.22),
                                    MedxTheme.cyanAccent.opacity(0.12)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .overlay(
                                Image(systemName: "sparkles.rectangle.stack.fill")
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundStyle(MedxTheme.indigoAccent)
                            )
                        }
                    }
                    .clipped()

                Text("\(subject.cardCount)")
                    .font(MedxFont.mono(11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.45), in: Capsule())
                    .padding(10)
            }
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 20,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 20,
                    style: .continuous
                )
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(subject.name)
                    .font(MedxFont.headline(15))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(subject.cardCount == 1 ? "1 visual card" : "\(subject.cardCount) visual cards")
                    .font(MedxFont.caption(11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .glassCard(cornerRadius: 20, shadowLevel: 1)
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
            self.subjects = try await FirestoreService.shared.fetchFlashcardSubjects(idToken: token)
            self.isLoading = false
        } catch {
            self.isLoading = false
        }
    }
}

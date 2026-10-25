import SwiftUI

/// Contact sheet of one subject's flashcards. The artwork variant is detected from the
/// device and the live window size, and can be overridden from the toolbar.
public struct FlashcardStudyView: View {
    public let subject: FlashcardSubject

    @State private var activeDeck: FlashcardDeckRequest?
    @State private var searchText = ""

    public init(subject: FlashcardSubject) {
        self.subject = subject
    }

    private var cards: [FlashcardCard] {
        subject.cards ?? []
    }

    private var filteredCards: [FlashcardCard] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return cards }
        return cards.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || ($0.chapter ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    public var body: some View {
        FlashcardLayoutReader { layout in
            Group {
                if cards.isEmpty {
                    MedxEmptyState(
                        "No flashcards yet",
                        symbol: "rectangle.stack.badge.minus",
                        message: "This subject does not contain any flashcards yet."
                    )
                } else {
                    grid(layout: layout)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
        }
        .navigationTitle(subject.name)
        .navigationSubtitle(cards.count == 1 ? "1 card" : "\(MedxFormat.count(cards.count)) cards")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                FlashcardArtworkMenu {
                    Image(systemName: "rectangle.on.rectangle.angled")
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search cards")
        .fullScreenCover(item: $activeDeck) { request in
            FlashcardDeckView(cards: request.cards, initialIndex: request.index)
        }
    }

    // MARK: - Grid

    private func grid(layout: FlashcardLayout) -> some View {
        // Landscape artwork is wide, so fewer and larger tiles read better.
        let minimum: CGFloat = layout.orientation == .landscape ? 230 : 150
        let maximum: CGFloat = layout.orientation == .landscape ? 320 : 210

        return ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: minimum, maximum: maximum), spacing: MedxSpace.m)],
                spacing: MedxSpace.m
            ) {
                ForEach(Array(filteredCards.enumerated()), id: \.element.id) { pair in
                    Button {
                        HapticManager.light()
                        activeDeck = FlashcardDeckRequest(index: pair.offset, cards: filteredCards)
                    } label: {
                        cardTile(pair.element, number: pair.offset + 1, layout: layout)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Flashcard \(pair.offset + 1), \(pair.element.name)")
                    .accessibilityHint("Opens the full-screen viewer")
                }
            }
            .padding(.horizontal, MedxSpace.l)
            .padding(.vertical, MedxSpace.m)

            if filteredCards.isEmpty {
                MedxEmptyState(
                    "No matches",
                    symbol: "magnifyingglass",
                    message: "No card in this subject matches “\(searchText)”."
                )
            }
        }
    }

    private func cardTile(_ card: FlashcardCard, number: Int, layout: FlashcardLayout) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                // `Color.clear` fixes the tile height to the artwork's aspect ratio, then
                // the image fills that box — the thumbnail never jumps as images load in.
                Color.clear
                    .aspectRatio(layout.aspectRatio, contentMode: .fit)
                    .overlay(
                        CachedAsyncImage(
                            url: URL(string: card.variants?.url(for: layout) ?? ""),
                            contentMode: .fill
                        )
                    )
                    .clipped()

                Text("\(number)")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.55), in: Capsule())
                    .padding(MedxSpace.s)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(card.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let chapter = card.chapter, !chapter.isEmpty {
                    Text(chapter)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MedxSpace.m)
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: MedxRadius.card, style: .continuous))
    }
}

/// Carries both the tapped card and the list it was tapped in, so the viewer pages
/// through exactly what is on screen (search results included).
struct FlashcardDeckRequest: Identifiable {
    let index: Int
    let cards: [FlashcardCard]

    var id: String { "\(index)-\(cards.count)" }
}

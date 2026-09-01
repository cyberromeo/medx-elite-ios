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
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    countLine

                    if cards.isEmpty {
                        ContentUnavailableView(
                            "No Flashcards",
                            systemImage: "rectangle.stack.badge.minus",
                            description: Text("This subject does not contain any flashcards yet.")
                        )
                        .padding(.top, 48)
                    } else if filteredCards.isEmpty {
                        ContentUnavailableView {
                            Label("No Matches", systemImage: "magnifyingglass")
                        } description: {
                            Text("No card in this subject matches “\(searchText)”.")
                        }
                        .padding(.top, 40)
                    } else {
                        grid(layout: layout)
                    }
                }
                .padding(.horizontal, MedxSurface.gutter)
                .padding(.top, 6)
                .padding(.bottom, 32)
            }
            .background(MedxSurface.groupedBackground)
        }
        .navigationTitle(subject.name)
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
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: "Search cards"
        )
        .fullScreenCover(item: $activeDeck) { request in
            FlashcardDeckView(cards: request.cards, initialIndex: request.index)
        }
    }

    private var countLine: some View {
        Text(cards.count == 1 ? "1 card" : "\(cards.count) cards")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 2)
    }

    // MARK: - Grid

    private func grid(layout: FlashcardLayout) -> some View {
        // Landscape artwork is wide, so fewer and larger tiles read better.
        let minimum: CGFloat = layout.orientation == .landscape ? 230 : 150
        let maximum: CGFloat = layout.orientation == .landscape ? 320 : 210

        return LazyVGrid(
            columns: [GridItem(.adaptive(minimum: minimum, maximum: maximum), spacing: 12)],
            spacing: 12
        ) {
            ForEach(Array(filteredCards.enumerated()), id: \.element.id) { index, card in
                Button {
                    HapticManager.light()
                    activeDeck = FlashcardDeckRequest(index: index, cards: filteredCards)
                } label: {
                    cardTile(card, number: index + 1, layout: layout)
                }
                .buttonStyle(.plain)
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityLabel("Flashcard \(index + 1), \(card.name)")
                .accessibilityHint("Opens the full-screen viewer")
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
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.5), in: Capsule())
                    .padding(8)
            }
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 14,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 14,
                    style: .continuous
                )
            )

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
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
        }
        .medxCard(cornerRadius: 14)
    }
}

/// Carries both the tapped card and the list it was tapped in, so the viewer pages
/// through exactly what is on screen (search results included).
struct FlashcardDeckRequest: Identifiable {
    let index: Int
    let cards: [FlashcardCard]

    var id: String { "\(index)-\(cards.count)" }
}

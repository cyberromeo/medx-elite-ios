import SwiftUI

/// Contact-sheet of one subject's flashcards. The artwork variant is detected from the
/// device and the live window size — there is no layout picker to get wrong.
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
                VStack(spacing: 14) {
                    summaryBar(layout: layout)

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
                .padding(.bottom, 36)
            }
            .background(Color(uiColor: .systemGroupedBackground))
        }
        .navigationTitle(subject.name)
        .navigationBarTitleDisplayMode(.large)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: "Search cards"
        )
        .fullScreenCover(item: $activeDeck) { request in
            FlashcardDeckView(cards: request.cards, initialIndex: request.index)
        }
    }

    // MARK: - Header

    private func summaryBar(layout: FlashcardLayout) -> some View {
        HStack(spacing: 10) {
            Label("\(cards.count) cards", systemImage: "rectangle.stack.fill")
                .font(MedxFont.label(12))
                .foregroundStyle(MedxTheme.indigoAccent)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(MedxTheme.indigoAccent.opacity(0.10), in: Capsule())

            Spacer(minLength: 8)

            // Read-only: shows what the app picked, it is not a control.
            Label(layout.label, systemImage: layout.iconName)
                .font(MedxFont.label(11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                .accessibilityLabel("Artwork detected for this device")
                .accessibilityValue(layout.label)
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
    }

    // MARK: - Grid

    private func grid(layout: FlashcardLayout) -> some View {
        // Landscape artwork is wide, so fewer and larger tiles read better.
        let minimum: CGFloat = layout.orientation == .landscape ? 230 : 150
        let maximum: CGFloat = layout.orientation == .landscape ? 320 : 210

        return LazyVGrid(
            columns: [GridItem(.adaptive(minimum: minimum, maximum: maximum), spacing: 14)],
            spacing: 14
        ) {
            ForEach(Array(filteredCards.enumerated()), id: \.element.id) { index, card in
                Button {
                    HapticManager.light()
                    activeDeck = FlashcardDeckRequest(index: index, cards: filteredCards)
                } label: {
                    cardTile(card, number: index + 1, layout: layout)
                }
                .buttonStyle(.plain)
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityLabel("Flashcard \(index + 1), \(card.name)")
                .accessibilityHint("Opens the full-screen viewer")
            }
        }
        .padding(.horizontal, 20)
    }

    private func cardTile(_ card: FlashcardCard, number: Int, layout: FlashcardLayout) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                // `Color.clear` fixes the tile height to the artwork's aspect ratio, then the
                // image fills that box — the thumbnail never jumps as images load in.
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
                    .font(MedxFont.mono(10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.45), in: Capsule())
                    .padding(8)
            }
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 18,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 18,
                    style: .continuous
                )
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(card.name)
                    .font(MedxFont.headline(13))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let chapter = card.chapter, !chapter.isEmpty {
                    Text(chapter)
                        .font(MedxFont.caption(11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .glassCard(cornerRadius: 18, shadowLevel: 1)
    }
}

/// Carries both the tapped card and the list it was tapped in, so the viewer pages
/// through exactly what is on screen (search results included).
struct FlashcardDeckRequest: Identifiable {
    let index: Int
    let cards: [FlashcardCard]

    var id: String { "\(index)-\(cards.count)" }
}

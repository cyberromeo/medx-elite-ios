import SwiftUI

/// Detects the flashcard artwork variant from the space it is given plus the device idiom,
/// and hands it to its content. Place it *outside* scroll views so it measures the screen.
struct FlashcardLayoutReader<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private let content: (FlashcardLayout) -> Content

    init(@ViewBuilder content: @escaping (FlashcardLayout) -> Content) {
        self.content = content
    }

    var body: some View {
        GeometryReader { geometry in
            content(
                FlashcardLayout.detect(
                    in: geometry.size,
                    isRegularWidth: horizontalSizeClass != .compact,
                    isPadIdiom: UIDevice.current.userInterfaceIdiom == .pad
                )
            )
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

/// Immersive flashcard photo-gallery viewer inspired by the native Photos experience.
/// The image remains the content; glass is reserved for navigation and controls.
public struct FlashcardDeckView: View {
    public let cards: [FlashcardCard]
    public let initialIndex: Int

    @State private var currentIndex: Int
    @State private var dismissOffset: CGFloat = 0
    @State private var showChrome = true
    @State private var zoomedPages: Set<Int> = []
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(cards: [FlashcardCard], initialIndex: Int = 0) {
        self.cards = cards
        self.initialIndex = initialIndex
        self._currentIndex = State(initialValue: initialIndex)
    }

    /// Panning a zoomed card must not fight the swipe-down-to-dismiss gesture.
    private var isZoomed: Bool {
        zoomedPages.contains(currentIndex)
    }

    public var body: some View {
        FlashcardLayoutReader { layout in
            ZStack {
                Color.black
                    .ignoresSafeArea()

                if !cards.isEmpty {
                    TabView(selection: $currentIndex) {
                        ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                            FlashcardGalleryPage(
                                card: card,
                                layout: layout,
                                chromeVisible: showChrome,
                                isZoomed: Binding(
                                    get: { zoomedPages.contains(index) },
                                    set: { zoomed in
                                        if zoomed {
                                            zoomedPages.insert(index)
                                        } else {
                                            zoomedPages.remove(index)
                                        }
                                    }
                                ),
                                onToggleChrome: {
                                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
                                        showChrome.toggle()
                                    }
                                }
                            )
                            .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .onChange(of: currentIndex) { _, _ in
                        HapticManager.selection()
                        // A fresh card starts unzoomed with its chrome back.
                        zoomedPages.removeAll()
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                            showChrome = true
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "No Flashcards",
                        systemImage: "rectangle.on.rectangle.slash",
                        description: Text("There are no flashcards to display.")
                    )
                    .foregroundStyle(.white)
                }

                if showChrome {
                    galleryChrome(layout: layout)
                        .transition(.opacity)
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .offset(y: dismissOffset)
        .opacity(max(0.55, 1 - Double(abs(dismissOffset)) / 420))
        .simultaneousGesture(dismissGesture, including: isZoomed ? .subviews : .all)
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
    }

    private func galleryChrome(layout: FlashcardLayout) -> some View {
        VStack(spacing: 0) {
            topBar(layout: layout)
            Spacer()
            bottomBar
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private func topBar(layout: FlashcardLayout) -> some View {
        HStack(spacing: 12) {
            Button {
                HapticManager.light()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .medxNavigationGlass(cornerRadius: 22, interactive: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close flashcard viewer")
            .accessibilityHint("Returns to the flashcard grid")

            Spacer()

            Text("\(min(currentIndex + 1, max(cards.count, 1))) of \(cards.count)")
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(minHeight: 36)
                .background(Color.black.opacity(0.34), in: Capsule())
                .accessibilityLabel("Flashcard position")
                .accessibilityValue("\(currentIndex + 1) of \(cards.count)")

            Spacer()

            // Detected, not chosen: kept as a label so the student can see which artwork
            // is on screen after a rotation.
            Image(systemName: layout.iconName)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 44, height: 44)
                .background(Color.black.opacity(0.34), in: Circle())
                .accessibilityLabel("Artwork detected for this device")
                .accessibilityValue(layout.label)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.72), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        )
    }

    @ViewBuilder
    private var bottomBar: some View {
        if cards.indices.contains(currentIndex) {
            let card = cards[currentIndex]

            VStack(alignment: .leading, spacing: 8) {
                Text(card.name)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(2)

                if let chapter = card.chapter, !chapter.isEmpty {
                    Text(chapter)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                }

                if cards.count > 1 {
                    pageIndicator
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.86)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea(edges: .bottom)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel(card.name)
            .accessibilityValue(chapterValue(for: card))
        }
    }

    /// A compact window over the dots so a 200-card deck does not draw 200 of them.
    private var pageIndicator: some View {
        let window = 7
        let half = window / 2
        let start = max(0, min(currentIndex - half, max(0, cards.count - window)))
        let end = min(cards.count, start + window)

        return HStack(spacing: 6) {
            ForEach(start..<end, id: \.self) { index in
                Capsule()
                    .fill(index == currentIndex ? Color.white : Color.white.opacity(0.32))
                    .frame(width: index == currentIndex ? 18 : 6, height: 6)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: currentIndex)
            }
        }
        .accessibilityHidden(true)
    }

    private func chapterValue(for card: FlashcardCard) -> String {
        if let chapter = card.chapter, !chapter.isEmpty {
            return chapter
        }
        return "Flashcard \(currentIndex + 1) of \(cards.count)"
    }

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                guard abs(value.translation.height) > abs(value.translation.width), value.translation.height > 0 else { return }
                dismissOffset = value.translation.height
            }
            .onEnded { value in
                guard abs(value.translation.height) > abs(value.translation.width), value.translation.height > 0 else {
                    dismissOffset = 0
                    return
                }

                if value.translation.height > 120 {
                    HapticManager.medium()
                    dismiss()
                } else {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.82)) {
                        dismissOffset = 0
                    }
                }
            }
    }
}

private struct FlashcardGalleryPage: View {
    let card: FlashcardCard
    let layout: FlashcardLayout
    let chromeVisible: Bool
    @Binding var isZoomed: Bool
    let onToggleChrome: () -> Void

    var body: some View {
        ZoomableFlashcardImage(
            url: URL(string: card.variants?.url(for: layout) ?? ""),
            accessibilityName: card.name,
            isZoomed: $isZoomed,
            onSingleTap: onToggleChrome
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, chromeVisible ? 12 : 0)
        .padding(.vertical, chromeVisible ? 76 : 0)
        .animation(.easeOut(duration: 0.22), value: chromeVisible)
    }
}

private struct ZoomableFlashcardImage: View {
    let url: URL?
    let accessibilityName: String
    @Binding var isZoomed: Bool
    let onSingleTap: () -> Void

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        CachedAsyncImage(url: url, contentMode: .fit)
            .scaleEffect(scale)
            .offset(offset)
            .contentShape(Rectangle())
            .gesture(zoomAndPanGesture)
            // Double tap has to be declared first or the single tap swallows it.
            .onTapGesture(count: 2) {
                HapticManager.selection()
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                    if scale > 1.05 {
                        resetZoom()
                    } else {
                        scale = 2
                        lastScale = 2
                    }
                }
                isZoomed = scale > 1.05
            }
            .onTapGesture {
                onSingleTap()
            }
            .accessibilityLabel(accessibilityName)
            .accessibilityHint("Double-tap to zoom. Pinch to zoom and drag when enlarged. Tap once to hide the controls.")
    }

    private func resetZoom() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
    }

    private var zoomAndPanGesture: some Gesture {
        SimultaneousGesture(
            MagnificationGesture()
                .onChanged { value in
                    scale = min(max(lastScale * value, 1), 4)
                }
                .onEnded { _ in
                    lastScale = scale
                    if scale <= 1 {
                        resetZoom()
                    }
                    isZoomed = scale > 1.05
                },
            DragGesture()
                .onChanged { value in
                    guard scale > 1 else { return }
                    offset = CGSize(
                        width: lastOffset.width + value.translation.width,
                        height: lastOffset.height + value.translation.height
                    )
                }
                .onEnded { _ in
                    lastOffset = offset
                }
        )
    }
}

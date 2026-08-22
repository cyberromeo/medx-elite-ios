import SwiftUI

/// Detects the flashcard artwork variant from the space it is given plus the device idiom,
/// then applies the student's override before handing the result to its content. Place it
/// *outside* scroll views so it measures the screen.
struct FlashcardLayoutReader<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject private var settings = FlashcardSettings.shared
    private let content: (FlashcardLayout) -> Content

    init(@ViewBuilder content: @escaping (FlashcardLayout) -> Content) {
        self.content = content
    }

    var body: some View {
        GeometryReader { geometry in
            let detected = FlashcardLayout.detect(
                in: geometry.size,
                isRegularWidth: horizontalSizeClass != .compact,
                isPadIdiom: UIDevice.current.userInterfaceIdiom == .pad
            )

            content(settings.artwork.layout(detected: detected))
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

/// Menu that lets the student pick the artwork variant instead of only being told which
/// one was detected. Used by the contact sheet and the full-screen viewer.
struct FlashcardArtworkMenu<Label: View>: View {
    @ObservedObject private var settings = FlashcardSettings.shared
    private let label: Label

    init(@ViewBuilder label: () -> Label) {
        self.label = label()
    }

    var body: some View {
        Menu {
            Picker("Artwork", selection: $settings.artwork) {
                ForEach(FlashcardArtworkPreference.allCases) { option in
                    Label(option.title, systemImage: option.iconName).tag(option)
                }
            }

            Divider()

            Toggle(isOn: $settings.rotatesLandscapeArtwork) {
                Label("Rotate landscape cards", systemImage: "rotate.right")
            }
        } label: {
            label
        }
        .accessibilityLabel("Artwork options")
        .accessibilityValue(settings.artwork.title)
    }
}

/// Immersive flashcard photo-gallery viewer inspired by the native Photos experience.
public struct FlashcardDeckView: View {
    public let cards: [FlashcardCard]
    public let initialIndex: Int

    @State private var currentIndex: Int
    @State private var dismissOffset: CGFloat = 0
    @State private var showChrome = true
    @State private var zoomedPages: Set<Int> = []
    @ObservedObject private var settings = FlashcardSettings.shared
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
                Color.black.ignoresSafeArea()

                if cards.isEmpty {
                    ContentUnavailableView(
                        "No Flashcards",
                        systemImage: "rectangle.on.rectangle.slash",
                        description: Text("There are no flashcards to display.")
                    )
                    .foregroundStyle(.white)
                } else {
                    pager(layout: layout)
                }
            }
            // Chrome is an overlay rather than the last child of the ZStack so it always
            // sits above the pager and keeps its hit testing.
            .overlay(alignment: .top) {
                if showChrome { topBar(layout: layout).transition(.opacity) }
            }
            .overlay(alignment: .bottom) {
                if showChrome { bottomBar.transition(.opacity) }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .offset(y: dismissOffset)
        .opacity(max(0.55, 1 - Double(abs(dismissOffset)) / 420))
        .simultaneousGesture(dismissGesture, including: isZoomed ? .subviews : .all)
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
    }

    // MARK: - Pager

    private func pager(layout: FlashcardLayout) -> some View {
        TabView(selection: $currentIndex) {
            ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                FlashcardGalleryPage(
                    card: card,
                    layout: layout,
                    chromeVisible: showChrome,
                    rotated: settings.rotatesLandscapeArtwork && layout.orientation == .landscape,
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
    }

    private func finishDismissDrag(_ translation: CGFloat) {
        if translation > 120 {
            HapticManager.medium()
            dismiss()
        } else {
            withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.82)) {
                dismissOffset = 0
            }
        }
    }

    /// Swipe down to dismiss. Attached at the root and simultaneously, so the pager's own
    /// horizontal scroll keeps working; suppressed while a card is zoomed because then the
    /// drag belongs to panning.
    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                guard value.translation.height > 0,
                      abs(value.translation.height) > abs(value.translation.width) else { return }
                dismissOffset = value.translation.height
            }
            .onEnded { value in
                guard value.translation.height > 0,
                      abs(value.translation.height) > abs(value.translation.width) else {
                    dismissOffset = 0
                    return
                }
                finishDismissDrag(value.translation.height)
            }
    }

    // MARK: - Chrome

    private func topBar(layout: FlashcardLayout) -> some View {
        HStack(spacing: 12) {
            // A plain button on a solid scrim. The previous version wrapped this label in
            // an *interactive* glass effect, which on iOS 26 consumes the touch itself —
            // the close button looked normal and simply never fired.
            circleButton(icon: "xmark", label: "Close flashcard viewer") {
                HapticManager.light()
                dismiss()
            }

            Spacer(minLength: 0)

            Text("\(min(currentIndex + 1, max(cards.count, 1))) of \(cards.count)")
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(minHeight: 34)
                .background(Color.black.opacity(0.45), in: Capsule())
                .accessibilityLabel("Flashcard position")
                .accessibilityValue("\(currentIndex + 1) of \(cards.count)")

            Spacer(minLength: 0)

            if layout.orientation == .landscape {
                circleButton(
                    icon: settings.rotatesLandscapeArtwork ? "rotate.left" : "rotate.right",
                    label: settings.rotatesLandscapeArtwork ? "Show upright" : "Rotate to fill the screen",
                    tinted: settings.rotatesLandscapeArtwork
                ) {
                    HapticManager.selection()
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                        settings.rotatesLandscapeArtwork.toggle()
                    }
                }
            }

            FlashcardArtworkMenu {
                Image(systemName: layout.iconName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.45), in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(
            LinearGradient(colors: [Color.black.opacity(0.72), .clear], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
        )
    }

    private func circleButton(
        icon: String,
        label: String,
        tinted: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(tinted ? Color.black : Color.white)
                .frame(width: 36, height: 36)
                .background(tinted ? Color.white : Color.black.opacity(0.45), in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
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
                    pageIndicator.padding(.top, 2)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [.clear, Color.black.opacity(0.86)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea(edges: .bottom)
                    .allowsHitTesting(false)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel(card.name)
            .accessibilityValue(card.chapter?.isEmpty == false
                                ? (card.chapter ?? "")
                                : "Flashcard \(currentIndex + 1) of \(cards.count)")
        }
    }

    /// A compact window over the dots so a 200-card deck does not draw 200 of them.
    private var pageIndicator: some View {
        let window = 7
        let start = max(0, min(currentIndex - window / 2, max(0, cards.count - window)))
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
}

// MARK: - One page

private struct FlashcardGalleryPage: View {
    let card: FlashcardCard
    let layout: FlashcardLayout
    let chromeVisible: Bool
    let rotated: Bool
    @Binding var isZoomed: Bool
    let onToggleChrome: () -> Void

    var body: some View {
        ZoomableFlashcardImage(
            url: URL(string: card.variants?.url(for: layout) ?? ""),
            accessibilityName: card.name,
            rotated: rotated,
            isZoomed: $isZoomed,
            onSingleTap: onToggleChrome
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, chromeVisible ? 10 : 0)
        .padding(.vertical, chromeVisible ? 72 : 0)
        .animation(.easeOut(duration: 0.22), value: chromeVisible)
    }
}

private struct ZoomableFlashcardImage: View {
    let url: URL?
    let accessibilityName: String
    let rotated: Bool
    @Binding var isZoomed: Bool
    let onSingleTap: () -> Void

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            CachedAsyncImage(url: url, contentMode: .fit)
                // A quarter turn needs the pre-rotation frame swapped, otherwise the
                // rotated artwork is letterboxed inside the portrait box.
                .frame(
                    width: rotated ? geo.size.height : geo.size.width,
                    height: rotated ? geo.size.width : geo.size.height
                )
                .rotationEffect(.degrees(rotated ? 90 : 0))
                .frame(width: geo.size.width, height: geo.size.height)
                .scaleEffect(scale)
                .offset(offset)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: rotated)
        }
        .contentShape(Rectangle())
        // Pinch runs alongside the pager's own scroll, so it is simultaneous...
        .simultaneousGesture(magnification)
        // ...but the pan gesture is only installed while zoomed in. Leaving it always on
        // is what made the deck only swipe from the screen edges: it claimed every drag
        // that started on the artwork and the pager never saw it.
        .gesture(pan, including: scale > 1.02 ? .all : .subviews)
        .onTapGesture(count: 2) { toggleZoom() }
        .onTapGesture { onSingleTap() }
        .accessibilityLabel(accessibilityName)
        .accessibilityHint("Swipe for the next card. Double-tap to zoom. Pinch to zoom, drag to pan when enlarged.")
    }

    private func toggleZoom() {
        HapticManager.selection()
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
            if scale > 1.05 {
                resetZoom()
            } else {
                scale = 2.4
                lastScale = 2.4
            }
        }
        isZoomed = scale > 1.05
    }

    private func resetZoom() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
    }

    private var magnification: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                // Deliberately does not publish `isZoomed` here: that lives on the parent,
                // and writing it every pinch frame would re-evaluate the whole pager.
                scale = min(max(lastScale * value.magnification, 1), 5)
            }
            .onEnded { _ in
                lastScale = scale
                if scale <= 1 { resetZoom() }
                isZoomed = scale > 1.02
            }
    }

    private var pan: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in lastOffset = offset }
    }
}

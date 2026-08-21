import SwiftUI

/// Immersive flashcard photo-gallery viewer inspired by the native Photos experience.
/// The image remains the content; glass is reserved for navigation and controls.
public struct FlashcardDeckView: View {
    public let cards: [FlashcardCard]
    public let initialIndex: Int

    @State private var currentIndex: Int
    @State private var selectedDevice: FlashcardDevice = .mobile
    @State private var selectedOrientation: FlashcardOrientation = .portrait
    @State private var dismissOffset: CGFloat = 0
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(cards: [FlashcardCard], initialIndex: Int = 0) {
        self.cards = cards
        self.initialIndex = initialIndex
        self._currentIndex = State(initialValue: initialIndex)
    }

    public var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            if !cards.isEmpty {
                TabView(selection: $currentIndex) {
                    ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                        FlashcardGalleryPage(
                            card: card,
                            device: selectedDevice,
                            orientation: selectedOrientation
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .onChange(of: currentIndex) { _, _ in
                    HapticManager.selection()
                }
            } else {
                ContentUnavailableView(
                    "No Flashcards",
                    systemImage: "rectangle.on.rectangle.slash",
                    description: Text("There are no flashcards to display.")
                )
                .foregroundStyle(.white)
            }

            galleryChrome
        }
        .offset(y: dismissOffset)
        .opacity(max(0.55, 1 - Double(abs(dismissOffset)) / 420))
        .simultaneousGesture(dismissGesture)
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
    }

    private var galleryChrome: some View {
        VStack(spacing: 0) {
            topBar
            Spacer()
            bottomBar
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                HapticManager.light()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .medxNavigationGlass(cornerRadius: 22, tint: .white, interactive: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close photo viewer")
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

            Menu {
                Section("Device View") {
                    ForEach(FlashcardDevice.allCases) { device in
                        Button {
                            selectedDevice = device
                            HapticManager.selection()
                        } label: {
                            if selectedDevice == device {
                                Label(device.rawValue, systemImage: "checkmark")
                            } else {
                                Text(device.rawValue)
                            }
                        }
                    }
                }

                Section("Orientation") {
                    ForEach(FlashcardOrientation.allCases) { orientation in
                        Button {
                            selectedOrientation = orientation
                            HapticManager.selection()
                        } label: {
                            if selectedOrientation == orientation {
                                Label(orientation.rawValue, systemImage: "checkmark")
                            } else {
                                Text(orientation.rawValue)
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: selectedDevice == .mobile
                      ? (selectedOrientation == .portrait ? "iphone" : "iphone.landscape")
                      : (selectedOrientation == .portrait ? "ipad" : "ipad.landscape"))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .medxNavigationGlass(cornerRadius: 22, tint: .white, interactive: true)
            }
            .accessibilityLabel("Preview layout")
            .accessibilityValue("\(selectedDevice.rawValue), \(selectedOrientation.rawValue)")
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
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(card.name)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    Spacer(minLength: 8)

                }

                if let chapter = card.chapter, !chapter.isEmpty {
                    Text(chapter)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
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
    let device: FlashcardDevice
    let orientation: FlashcardOrientation

    var body: some View {
        let urlString = card.variants?.urlFor(device: device, orientation: orientation)
        let url = URL(string: urlString ?? "")

        ZoomableFlashcardImage(url: url, accessibilityName: card.name)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 76)
    }
}

private struct ZoomableFlashcardImage: View {
    let url: URL?
    let accessibilityName: String

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
            .onTapGesture(count: 2) {
                HapticManager.selection()
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                    if scale > 1.05 {
                        scale = 1
                        lastScale = 1
                        offset = .zero
                        lastOffset = .zero
                    } else {
                        scale = 2
                        lastScale = 2
                    }
                }
            }
            .accessibilityLabel(accessibilityName)
            .accessibilityHint("Double-tap to zoom. Pinch to zoom and drag when enlarged.")
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
                        scale = 1
                        offset = .zero
                        lastOffset = .zero
                    }
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

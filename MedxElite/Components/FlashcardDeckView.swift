import SwiftUI

public struct FlashcardDeckView: View {
    public let cards: [FlashcardCard]
    public let initialIndex: Int

    @State private var currentIndex: Int
    @State private var selectedDevice: FlashcardDevice = .mobile
    @State private var selectedOrientation: FlashcardOrientation = .portrait
    @State private var isZoomed = false
    @State private var dragOffset: CGSize = .zero
    @Environment(\.dismiss) private var dismiss

    public init(cards: [FlashcardCard], initialIndex: Int = 0) {
        self.cards = cards
        self.initialIndex = initialIndex
        self._currentIndex = State(initialValue: initialIndex)
    }

    public var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                // Header Navigation
                HStack {
                    Button {
                        HapticManager.light()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Text("\(currentIndex + 1) of \(cards.count)")
                        .font(MedxFont.monospacedDigits(14, weight: .bold))
                        .foregroundColor(.primary)

                    Spacer()

                    // Layout Picker Menu
                    Menu {
                        Section("Device View") {
                            ForEach(FlashcardDevice.allCases) { dev in
                                Button {
                                    selectedDevice = dev
                                    HapticManager.selection()
                                } label: {
                                    if selectedDevice == dev {
                                        Label(dev.rawValue, systemImage: "checkmark")
                                    } else {
                                        Text(dev.rawValue)
                                    }
                                }
                            }
                        }

                        Section("Orientation") {
                            ForEach(FlashcardOrientation.allCases) { ori in
                                Button {
                                    selectedOrientation = ori
                                    HapticManager.selection()
                                } label: {
                                    if selectedOrientation == ori {
                                        Label(ori.rawValue, systemImage: "checkmark")
                                    } else {
                                        Text(ori.rawValue)
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: selectedDevice == .mobile
                              ? (selectedOrientation == .portrait ? "iphone" : "iphone.landscape")
                              : (selectedOrientation == .portrait ? "ipad" : "ipad.landscape"))
                            .font(.headline)
                            .foregroundColor(MedxTheme.primaryPurple)
                            .padding(8)
                            .background(MedxTheme.primaryPurple.opacity(0.12))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 8)

                if cards.indices.contains(currentIndex) {
                    let card = cards[currentIndex]

                    VStack(spacing: 12) {
                        Text(card.name)
                            .font(MedxFont.rounded(18, weight: .bold))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)

                        if let chap = card.chapter, !chap.isEmpty {
                            Text(chap)
                                .font(MedxFont.rounded(13, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 8)

                    // Card Canvas with Interactive Pan & Zoom
                    GeometryReader { geo in
                        let urlStr = card.variants?.urlFor(device: selectedDevice, orientation: selectedOrientation)
                        let url = URL(string: urlStr ?? "")

                        ZStack {
                            CachedAsyncImage(url: url, contentMode: .fit)
                                .frame(maxWidth: geo.size.width - 24, maxHeight: geo.size.height - 24)
                                .liquidGlassCard(cornerRadius: 20, glowColor: MedxTheme.primaryPurple)
                                .offset(x: dragOffset.width)
                                .rotationEffect(.degrees(Double(dragOffset.width / 20)))
                                .gesture(
                                    DragGesture()
                                        .onChanged { gesture in
                                            dragOffset = gesture.translation
                                        }
                                        .onEnded { gesture in
                                            if gesture.translation.width < -60 && currentIndex + 1 < cards.count {
                                                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                                    currentIndex += 1
                                                    HapticManager.light()
                                                }
                                            } else if gesture.translation.width > 60 && currentIndex > 0 {
                                                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                                    currentIndex -= 1
                                                    HapticManager.light()
                                                }
                                            }
                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                                dragOffset = .zero
                                            }
                                        }
                                )
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    // Bottom navigation arrows
                    HStack(spacing: 40) {
                        Button {
                            if currentIndex > 0 {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                    currentIndex -= 1
                                    HapticManager.selection()
                                }
                            }
                        } label: {
                            Image(systemName: "chevron.left.circle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(currentIndex > 0 ? MedxTheme.primaryPurple : .secondary.opacity(0.3))
                        }
                        .disabled(currentIndex == 0)

                        Button {
                            if currentIndex + 1 < cards.count {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                    currentIndex += 1
                                    HapticManager.selection()
                                }
                            }
                        } label: {
                            Image(systemName: "chevron.right.circle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(currentIndex + 1 < cards.count ? MedxTheme.primaryPurple : .secondary.opacity(0.3))
                        }
                        .disabled(currentIndex + 1 >= cards.count)
                    }
                    .padding(.vertical, 20)
                }
            }
        }
    }
}

import SwiftUI

public struct FlashcardStudyView: View {
    public let subject: FlashcardSubject
    @State private var selectedDevice: FlashcardDevice = .mobile
    @State private var selectedOrientation: FlashcardOrientation = .portrait
    @State private var activeDeckStartIndex: Int?

    public init(subject: FlashcardSubject) {
        self.subject = subject
    }

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 14)
    ]

    public var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                // Header & Layout Switcher Bar
                HStack {
                    Text("\(subject.cardCount) cards")
                        .font(MedxFont.label(13))
                        .foregroundColor(.secondary)

                    Spacer()

                    // Device & Orientation Selector
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
                        HStack(spacing: 6) {
                            Image(systemName: selectedDevice == .mobile
                                  ? (selectedOrientation == .portrait ? "iphone" : "iphone.landscape")
                                  : (selectedOrientation == .portrait ? "ipad" : "ipad.landscape"))
                            Text("\(selectedDevice.rawValue) \(selectedOrientation.rawValue)")
                                .font(MedxFont.label(12))
                        }
                        .foregroundColor(MedxTheme.primaryPurple)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(MedxTheme.primaryPurple.opacity(0.12))
                        .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                // Cards Grid
                let cards = subject.cards ?? []
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                        Button {
                            HapticManager.light()
                            activeDeckStartIndex = index
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                let urlStr = card.variants?.urlFor(device: selectedDevice, orientation: selectedOrientation)
                                let url = URL(string: urlStr ?? "")

                                CachedAsyncImage(url: url, contentMode: .fill)
                                    .frame(height: 140)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                                Text(card.name)
                                    .font(MedxFont.headline(13))
                                    .foregroundColor(.primary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                            .padding(10)
                            .liquidGlassCard(cornerRadius: 16)
                        }
                        .buttonStyle(BouncyButtonStyle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle(subject.name)
        .navigationBarTitleDisplayMode(.large)
        .fullScreenCover(item: Binding(
            get: { activeDeckStartIndex.map { DeckIndexWrapper(index: $0) } },
            set: { activeDeckStartIndex = $0?.index }
        )) { wrapper in
            FlashcardDeckView(cards: subject.cards ?? [], initialIndex: wrapper.index)
        }
    }
}

private struct DeckIndexWrapper: Identifiable {
    let index: Int
    var id: Int { index }
}

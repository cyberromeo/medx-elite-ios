import SwiftUI

public struct CachedAsyncImage: View {
    public let url: URL?
    public var contentMode: ContentMode = .fit

    @State private var uiImage: UIImage?
    @State private var isLoading = false

    public init(url: URL?, contentMode: ContentMode = .fit) {
        self.url = url
        self.contentMode = contentMode
    }

    public var body: some View {
        ZStack {
            if let image = uiImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else if isLoading {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                    ProgressView()
                }
                .frame(minHeight: 120)
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.03))
                    .overlay(
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundColor(.secondary.opacity(0.6))
                    )
                    .frame(minHeight: 120)
            }
        }
        .task(id: url) {
            await loadImage()
        }
    }

    private func loadImage() async {
        guard let url = url else { return }
        let key = url.absoluteString

        if let cached = ImageCache.shared.get(forKey: key) {
            self.uiImage = cached
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let img = UIImage(data: data) {
                ImageCache.shared.set(img, forKey: key)
                withAnimation(.easeOut(duration: 0.25)) {
                    self.uiImage = img
                }
            }
        } catch {
            // Failed to load
        }
    }
}

private final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 200
        cache.totalCostLimit = 100 * 1024 * 1024 // 100 MB
    }

    func get(forKey key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func set(_ image: UIImage, forKey key: String) {
        let cost = Int(image.size.width * image.size.height * 4)
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }
}

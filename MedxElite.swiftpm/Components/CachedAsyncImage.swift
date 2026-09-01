import SwiftUI
import ImageIO

/// Async image with a three-tier cache (memory → disk → network) and a downsampling
/// decode.
///
/// The flashcard artwork and QBank figures are full-resolution web exports; decoding them
/// at native size cost tens of megabytes of RAM per card and dropped frames while the
/// contact sheet scrolled. `MedxImageLoader` decodes a thumbnail sized for the screen
/// instead, off the main thread, and keeps the bytes on disk so the deck does not
/// re-download on every launch.
public struct CachedAsyncImage: View {
    public let url: URL?
    public var contentMode: ContentMode
    /// Longest edge of the decoded bitmap, in pixels.
    public var maxPixelSize: CGFloat

    @State private var image: UIImage?
    @State private var isLoading = false
    @State private var didFail = false

    public init(url: URL?, contentMode: ContentMode = .fit, maxPixelSize: CGFloat = 1800) {
        self.url = url
        self.contentMode = contentMode
        self.maxPixelSize = maxPixelSize
    }

    public var body: some View {
        content
            .task(id: url) { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: contentMode)
                .accessibilityHidden(true)
        } else if didFail {
            placeholder(icon: "photo.badge.exclamationmark")
        } else if isLoading {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(MedxSurface.tileFill)
                ProgressView()
                    .controlSize(.small)
            }
            .frame(minHeight: 110)
        } else {
            placeholder(icon: "photo")
        }
    }

    private func placeholder(icon: String) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(MedxSurface.tileFill)
            .overlay(
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(.tertiary)
            )
            .frame(minHeight: 110)
            .accessibilityHidden(true)
    }

    private func load() async {
        guard let url else {
            image = nil
            return
        }

        // A memory hit renders in the same frame — no spinner, no fade.
        if let cached = MedxImageLoader.shared.cachedImage(for: url, maxPixelSize: maxPixelSize) {
            image = cached
            isLoading = false
            didFail = false
            return
        }

        isLoading = true
        didFail = false
        let loaded = await MedxImageLoader.shared.image(for: url, maxPixelSize: maxPixelSize)
        guard !Task.isCancelled else { return }
        isLoading = false

        if let loaded {
            withAnimation(.easeOut(duration: 0.18)) { image = loaded }
        } else {
            didFail = true
        }
    }
}

/// Shared image cache and loader. Requests for the same URL coalesce onto one download.
final class MedxImageLoader {
    static let shared = MedxImageLoader()

    private let memory = NSCache<NSString, UIImage>()
    private let directory: URL
    private let session: URLSession
    private let lock = NSLock()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    private init() {
        // `directory` and `session` have no default value, so they must be assigned before
        // anything touches `self` — including the cache that *does* have one.
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let folder = base.appendingPathComponent("MedxImages", isDirectory: true)
        directory = folder

        let configuration = URLSessionConfiguration.default
        configuration.httpMaximumConnectionsPerHost = 6
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: configuration)

        if !fileManager.fileExists(atPath: folder.path) {
            try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        }

        memory.countLimit = 160
        memory.totalCostLimit = 120 * 1024 * 1024
    }

    private func key(_ url: URL, maxPixelSize: CGFloat) -> String {
        "\(Int(maxPixelSize))|\(url.absoluteString)"
    }

    /// Synchronous memory-only lookup, so an already-decoded image can be shown without a
    /// state round trip and the flicker that comes with it.
    func cachedImage(for url: URL, maxPixelSize: CGFloat) -> UIImage? {
        memory.object(forKey: key(url, maxPixelSize: maxPixelSize) as NSString)
    }

    func image(for url: URL, maxPixelSize: CGFloat) async -> UIImage? {
        let cacheKey = key(url, maxPixelSize: maxPixelSize)
        if let hit = memory.object(forKey: cacheKey as NSString) { return hit }

        // The lock is taken inside synchronous helpers on purpose: `NSLock.lock()` is
        // unavailable directly from an async context, and holding a lock across an
        // `await` would be wrong anyway.
        let task = claimTask(cacheKey: cacheKey, url: url, maxPixelSize: maxPixelSize)
        let result = await task.value
        releaseTask(cacheKey: cacheKey)
        return result
    }

    /// Returns the in-flight download for this key, starting one if there isn't one, so a
    /// grid showing the same artwork twice fetches it once.
    private func claimTask(cacheKey: String, url: URL, maxPixelSize: CGFloat) -> Task<UIImage?, Never> {
        lock.lock()
        defer { lock.unlock() }

        if let existing = inFlight[cacheKey] { return existing }

        let task = Task<UIImage?, Never> { [weak self] in
            await self?.fetch(url: url, maxPixelSize: maxPixelSize, cacheKey: cacheKey) ?? nil
        }
        inFlight[cacheKey] = task
        return task
    }

    private func releaseTask(cacheKey: String) {
        lock.lock()
        defer { lock.unlock() }
        inFlight[cacheKey] = nil
    }

    private func fetch(url: URL, maxPixelSize: CGFloat, cacheKey: String) async -> UIImage? {
        let fileURL = diskURL(for: url)

        if let data = try? Data(contentsOf: fileURL), !data.isEmpty {
            if let decoded = Self.downsample(data: data, maxPixelSize: maxPixelSize) {
                store(decoded, forKey: cacheKey)
                return decoded
            }
            // Corrupt or truncated: drop it and go back to the network.
            try? FileManager.default.removeItem(at: fileURL)
        }

        guard let data = await download(url: url), !data.isEmpty else { return nil }
        try? data.write(to: fileURL, options: .atomic)

        guard let decoded = Self.downsample(data: data, maxPixelSize: maxPixelSize) else { return nil }
        store(decoded, forKey: cacheKey)
        return decoded
    }

    private func download(url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        // The question-image CDN rejects requests with no browser-shaped User-Agent.
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }

    private func store(_ image: UIImage, forKey key: String) {
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        memory.setObject(image, forKey: key as NSString, cost: cost)
    }

    private func diskURL(for url: URL) -> URL {
        // A stable, filesystem-safe name. Hashing keeps long signed CDN URLs in range.
        var hash: UInt64 = 5381
        for byte in url.absoluteString.utf8 {
            hash = (hash << 5) &+ hash &+ UInt64(byte)
        }
        let extensionName = url.pathExtension.isEmpty ? "img" : url.pathExtension.lowercased()
        return directory.appendingPathComponent(String(format: "%016llx.%@", hash, extensionName))
    }

    /// Decodes straight to the size that will be drawn. `ImageIO` does the scaling during
    /// decode, so the full-size bitmap is never materialised. Runs off the main thread, so
    /// it deliberately reads nothing from `UIScreen`.
    private static func downsample(data: Data, maxPixelSize: CGFloat) -> UIImage? {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else {
            return UIImage(data: data)
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(maxPixelSize, 64)
        ]

        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            return UIImage(data: data)
        }
        // Scale 1: `maxPixelSize` is already expressed in pixels and sized generously for
        // a 3x display, and SwiftUI scales the result down to the frame it is given.
        return UIImage(cgImage: thumbnail)
    }

    /// Total bytes the downloaded originals occupy. Surfaced in Settings.
    func diskSize() -> Int64 {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }

        return contents.reduce(into: Int64(0)) { total, url in
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
    }

    func clear() {
        memory.removeAllObjects()
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}


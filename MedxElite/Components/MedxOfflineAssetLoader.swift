import Foundation
import AVFoundation
import UniformTypeIdentifiers

// MARK: - Custom scheme

/// The URL scheme downloaded classes are played back through.
///
/// AVFoundation refuses to load an HLS playlist from a `file://` URL, which is why offline
/// playback used to be served by the app's own loopback HTTP server. A custom scheme plus an
/// `AVAssetResourceLoaderDelegate` gets the same result without a socket: because the saved
/// `local.m3u8` was rewritten to plain sibling filenames, AVFoundation resolves every segment
/// against this base URL and asks the delegate for those too.
public enum MedxOfflineScheme {
    public static let scheme = "medxoffline"

    /// `medxoffline:///<folder>/local.m3u8`
    ///
    /// The folder is carried in the *path*, not the authority: URL parsing lower-cases a
    /// host, and download folders are derived from case-sensitive video ids.
    public static func assetURL(
        videoId: String,
        file: String = VideoDownloadStore.playlistFileName
    ) -> URL? {
        let folder = VideoDownloadStore.folderName(for: videoId)
        guard !folder.isEmpty else { return nil }
        return URL(string: "\(scheme):///\(folder)/\(file)")
    }

    /// Maps a request back onto the app container, refusing anything that tries to climb out.
    static func fileURL(for url: URL) -> URL? {
        guard url.scheme == scheme else { return nil }
        let components = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard components.count == 2 else { return nil }
        let folder = components[0]
        let file = components[1]
        guard isSafeComponent(folder), isSafeComponent(file) else { return nil }

        return VideoDownloadStore.rootDirectory()
            .appendingPathComponent(folder, isDirectory: true)
            .appendingPathComponent(file)
    }

    static func isSafeComponent(_ value: String) -> Bool {
        !value.isEmpty && !value.contains("/") && !value.contains("\\") && !value.contains("..")
    }

    /// The UTI AVFoundation wants in `contentInformationRequest.contentType`. Getting this
    /// wrong on the playlist is the difference between playback and a silent failure.
    static func contentType(for fileName: String) -> String {
        switch (fileName as NSString).pathExtension.lowercased() {
        case "m3u8", "m3u":
            return UTType(mimeType: "application/vnd.apple.mpegurl")?.identifier ?? "public.m3u-playlist"
        case "ts":
            return UTType(mimeType: "video/mp2t")?.identifier ?? "public.mpeg-2-transport-stream"
        case "mp4", "m4s", "m4v":
            return UTType.mpeg4Movie.identifier
        case "m4a":
            return UTType.mpeg4Audio.identifier
        case "aac":
            return UTType(mimeType: "audio/aac")?.identifier ?? "public.aac-audio"
        case "vtt":
            return UTType(mimeType: "text/vtt")?.identifier ?? "org.w3.webvtt"
        default:
            return UTType.data.identifier
        }
    }
}

// MARK: - Resource loader

/// Serves a finished download to `AVPlayer` straight off the disk.
///
/// **Must be retained by the caller.** `AVAssetResourceLoader` holds its delegate weakly, so
/// letting this go out of scope makes playback stall with no error — which is the classic way
/// this design fails silently.
public final class MedxOfflineAssetLoader: NSObject, AVAssetResourceLoaderDelegate {
    /// The queue the delegate callbacks arrive on. Serial: HLS asks for the playlist, then
    /// segments in order, and local reads are fast enough that queueing them is simpler and
    /// safer than fanning out.
    public let queue = DispatchQueue(label: "quest.srihari.medxelite.offline-loader", qos: .userInitiated)

    public override init() {
        super.init()
    }

    /// Convenience: an asset already wired to this loader.
    public func makeAsset(videoId: String) -> AVURLAsset? {
        guard let url = MedxOfflineScheme.assetURL(videoId: videoId) else { return nil }
        let asset = AVURLAsset(url: url)
        asset.resourceLoader.setDelegate(self, queue: queue)
        return asset
    }

    public func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        guard let url = loadingRequest.request.url, url.scheme == MedxOfflineScheme.scheme else {
            return false
        }

        guard let fileURL = MedxOfflineScheme.fileURL(for: url) else {
            loadingRequest.finishLoading(with: Self.error(.badURL, url))
            return true
        }

        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = (attributes[.size] as? NSNumber)?.int64Value,
              size > 0 else {
            loadingRequest.finishLoading(with: Self.error(.fileDoesNotExist, url))
            return true
        }

        if let information = loadingRequest.contentInformationRequest {
            information.contentType = MedxOfflineScheme.contentType(for: fileURL.lastPathComponent)
            information.contentLength = size
            information.isByteRangeAccessSupported = true
            information.isEntireLengthAvailableOnDemand = true
        }

        guard let dataRequest = loadingRequest.dataRequest else {
            loadingRequest.finishLoading()
            return true
        }

        respond(to: dataRequest, from: fileURL, size: size, request: loadingRequest)
        return true
    }

    /// Nothing is held pending — every request is answered before `shouldWait…` returns — so
    /// a cancellation has nothing left to undo. Implemented anyway because AVFoundation logs
    /// a complaint when the delegate does not respond to it.
    public func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        didCancel loadingRequest: AVAssetResourceLoadingRequest
    ) {
    }

    // MARK: - Reading

    private func respond(
        to dataRequest: AVAssetResourceLoadingDataRequest,
        from fileURL: URL,
        size: Int64,
        request: AVAssetResourceLoadingRequest
    ) {
        // `currentOffset` already accounts for whatever has been handed over so far; taking
        // the larger of the two is what keeps a resumed range request honest.
        let offset = max(dataRequest.currentOffset, dataRequest.requestedOffset)
        guard offset >= 0, offset < size else {
            request.finishLoading()
            return
        }

        let remaining = Int(size - offset)
        let length = dataRequest.requestsAllDataToEndOfResource
            ? remaining
            : min(dataRequest.requestedLength, remaining)

        guard length > 0 else {
            request.finishLoading()
            return
        }

        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            request.finishLoading(with: Self.error(.cannotOpenFile, fileURL))
            return
        }
        defer { try? handle.close() }

        do {
            if offset > 0 {
                try handle.seek(toOffset: UInt64(offset))
            }
            let data = try handle.read(upToCount: length) ?? Data()
            guard !data.isEmpty else {
                request.finishLoading(with: Self.error(.zeroByteResource, fileURL))
                return
            }
            dataRequest.respond(with: data)
            request.finishLoading()
        } catch {
            request.finishLoading(with: error)
        }
    }

    private static func error(_ code: URLError.Code, _ url: URL) -> NSError {
        NSError(
            domain: NSURLErrorDomain,
            code: code.rawValue,
            userInfo: [
                NSLocalizedDescriptionKey: "The saved copy of this class is unreadable.",
                NSURLErrorFailingURLStringErrorKey: url.absoluteString
            ]
        )
    }
}

import Foundation
import Network
import Combine

/// A lightweight local HTTP proxy that intercepts HLS requests (.m3u8 and .ts)
/// and forwards them to the real server with spoofed headers extracted from
/// the original app's network traffic (HAR capture).
///
/// Usage:
///   let proxy = HLSProxyServer.shared
///   proxy.start()
///   let localURL = proxy.proxiedURL(for: originalStreamURL)
///   // Feed localURL to AVPlayer
///
public final class HLSProxyServer: ObservableObject {
    public static let shared = HLSProxyServer()

    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var port: UInt16 = 0

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.medxelite.hlsproxy", qos: .userInitiated)
    private let session: URLSession

    // MARK: - Spoofed Headers (from HAR capture)
    fileprivate static let spoofedHeaders: [String: String] = [
        "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",
        "Origin": "capacitor://localhost",
        "Sec-Fetch-Site": "cross-site",
        "Sec-Fetch-Mode": "no-cors",
        "Sec-Fetch-Dest": "video",
        "Accept": "*/*",
        "Accept-Encoding": "identity",
        "Accept-Language": "en-IN,en;q=0.9",
        "Connection": "keep-alive",
        "Priority": "u=3, i"
    ]

    // API headers for arisemedicalacademy.com endpoints
    fileprivate static let apiHeaders: [String: String] = [
        "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",
        "Origin": "capacitor://localhost",
        "appId": "mobile",
        "deviceType": "ios",
        "appVersion": "1.5.6",
        "Sec-Fetch-Site": "cross-site",
        "Sec-Fetch-Mode": "cors",
        "Sec-Fetch-Dest": "empty",
        "Accept": "application/json, text/plain, */*",
        "Accept-Language": "en-IN,en;q=0.9",
        "Accept-Encoding": "gzip, deflate, br, zstd",
        "Connection": "keep-alive",
        "DeviceId": "54B4406E-A891-4769-BB6D-2C714C967ED0",
        "DeviceInfo": "{\"model\":\"iPhone15,2\",\"osVersion\":\"27.0\",\"manufacturer\":\"Apple\",\"platform\":\"ios\"}"
    ]

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        config.httpMaximumConnectionsPerHost = 8
        session = URLSession(configuration: config)
    }

    // MARK: - Public API

    /// Start the local proxy server
    @MainActor
    public func start() {
        // `listener != nil` covers the window between binding and `.ready`: starting twice
        // there used to orphan the first listener and report the wrong port.
        if isRunning || listener != nil { return }

        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let newListener = try NWListener(using: parameters, on: .any)

            newListener.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    switch state {
                    case .ready:
                        if let portVal = self.listener?.port?.rawValue {
                            self.port = portVal
                            self.isRunning = true
                            print("[HLSProxy] Running on port \(portVal)")
                        }
                    case .failed(let error):
                        print("[HLSProxy] Failed: \(error)")
                        self.isRunning = false
                        self.port = 0
                        // Let a later `start()` try again on a fresh listener.
                        self.listener?.cancel()
                        self.listener = nil
                    case .cancelled:
                        self.isRunning = false
                        self.port = 0
                        // **This line is the bug that made every other symptom permanent.**
                        //
                        // `.failed` above clears `listener`; this branch did not. `start()` bails out
                        // early on `if isRunning || listener != nil`, so once a listener had been
                        // cancelled — which is what iOS does to a listening socket when it suspends the
                        // process — the guard saw a non-nil listener forever and the proxy could never
                        // be rebound for the life of the process. Backgrounding the app once meant no
                        // video would stream again until it was force-quit.
                        self.listener = nil
                    default:
                        break
                    }
                }
            }

            newListener.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }

            self.listener = newListener
            newListener.start(queue: queue)
        } catch {
            print("[HLSProxy] Failed to start: \(error)")
        }
    }

    /// Stop the proxy server.
    ///
    /// `@MainActor` and setting the published pair **synchronously**, which matters for `restart()`:
    /// this used to hop onto main with `DispatchQueue.main.async`, so a `stop()` immediately followed by
    /// a `start()` would find `isRunning` still `true` and bail out on `start()`'s own guard. The
    /// listener would be gone and nothing would replace it.
    @MainActor
    public func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        port = 0
    }

    /// `start()` binds asynchronously, so a caller that needs a URL immediately has to wait for the
    /// port. Returns false if the listener never came up.
    ///
    /// **It probes rather than trusting its own flags.** `isRunning` and `port` are only ever updated
    /// from `NWListener`'s state handler, and that handler does not run while the process is suspended —
    /// so after the app has been backgrounded and reopened, both can still describe a socket the kernel
    /// closed. This used to return `true` on that stale pair and hand `AVPlayer` a URL on a dead port,
    /// which is exactly the "no video plays after I reopen the app" report: connection refused,
    /// `AVPlayerItem.status == .failed`, playback error.
    ///
    /// One `GET /health` against the bound port settles it in a few milliseconds. If nothing answers,
    /// the listener is torn down and rebound.
    @MainActor
    public func waitUntilRunning(timeout: TimeInterval = 3) async -> Bool {
        if isRunning, port > 0, await isAnswering() { return true }

        // Either never started, or bound to a port that no longer answers. Both want a fresh listener.
        restart()

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isRunning, port > 0 { return true }
            try? await Task.sleep(nanoseconds: 60_000_000)
        }
        return isRunning && port > 0
    }

    /// Tear down and rebind. The port changes, which is fine — every caller builds its URL through
    /// `proxiedURL(for:)` at the moment it needs one.
    @MainActor
    public func restart() {
        stop()
        start()
    }

    /// Rebind **only if the socket has actually gone.** What the app calls when it comes back to the
    /// foreground.
    ///
    /// The distinction matters: audio is a declared background mode, so a class can still be playing
    /// through this proxy when the app becomes active again, and an unconditional `restart()` would cut
    /// it off mid-segment. A probe costs a few milliseconds and a round trip to localhost.
    @MainActor
    public func revalidate() async {
        if isRunning, port > 0, await isAnswering() { return }
        restart()
    }

    /// Does the bound port actually answer? A listener object existing is not the same claim.
    @MainActor
    private func isAnswering() async -> Bool {
        guard port > 0, let url = URL(string: "http://127.0.0.1:\(port)/health") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 0.6
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (_, response) = try? await session.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    /// Convert a remote stream URL to a local proxied URL
    public func proxiedURL(for remoteURL: String) -> URL? {
        guard isRunning, port > 0 else { return nil }
        let encoded = remoteURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? remoteURL
        return URL(string: "http://127.0.0.1:\(port)/proxy?url=\(encoded)")
    }

    /// The exact header set the upstream CDN expects for a given URL. Shared with
    /// `VideoDownloadStore` so proxied playback and offline downloads cannot drift apart.
    fileprivate static func spoofHeaders(for targetURL: URL) -> [String: String] {
        let host = targetURL.host ?? ""
        let pathExt = targetURL.pathExtension.lowercased()
        // Playback assets: playlists, segments, init sections and keys.
        let isPlaybackAsset = ["m3u8", "ts", "m4s", "mp4", "m4v", "m4a", "aac", "key"].contains(pathExt)
        var headers: [String: String] = [:]

        if host.contains("liveplayback") || isPlaybackAsset {
            // HLS streaming headers
            headers = spoofedHeaders
            headers["Host"] = host
            headers["X-Playback-Session-Id"] = UUID().uuidString
        } else if host.contains("arisemedicalacademy") {
            // API headers
            headers = apiHeaders
            headers["Host"] = host
        } else if host.contains("cloudfront") {
            // CDN headers
            headers["User-Agent"] = spoofedHeaders["User-Agent"]
            headers["Host"] = host
            headers["Sec-Fetch-Site"] = "cross-site"
            headers["Sec-Fetch-Mode"] = "no-cors"
        } else {
            // Signed segment URLs are often extensionless on hosts we have never seen.
            // Sending no headers at all is what got those downloads rejected with a 403,
            // so the HLS set is the fallback rather than a special case.
            headers = spoofedHeaders
            headers["Host"] = host
            headers["X-Playback-Session-Id"] = UUID().uuidString
        }

        return headers
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self, let data = data, !data.isEmpty else {
                connection.cancel()
                return
            }

            guard let requestString = String(data: data, encoding: .utf8) else {
                self.sendError(connection: connection, code: 400, message: "Bad Request")
                return
            }

            // Parse the HTTP request line
            let lines = requestString.components(separatedBy: "\r\n")
            guard let firstLine = lines.first else {
                self.sendError(connection: connection, code: 400, message: "Bad Request")
                return
            }

            let parts = firstLine.components(separatedBy: " ")
            guard parts.count >= 2 else {
                self.sendError(connection: connection, code: 400, message: "Bad Request")
                return
            }

            // Only GET /proxy?url=… is served now that offline playback is handled by
            // `MedxOfflineAssetLoader` rather than a second route on this server.
            let path = parts[1]

            // `/health` exists so `waitUntilRunning` can ask the socket rather than trusting a
            // `@Published` flag that stops being updated the moment the process suspends.
            if path.hasPrefix("/health") {
                self.sendHealth(connection: connection)
                return
            }

            // Extract the target URL from query parameter
            if path.hasPrefix("/proxy?url="),
               let urlComponent = path.components(separatedBy: "url=").last,
               let decodedURL = urlComponent.removingPercentEncoding,
               let targetURL = URL(string: decodedURL) {
                self.proxyRequest(to: targetURL, connection: connection)
            } else {
                self.sendError(connection: connection, code: 404, message: "Not Found")
            }
        }
    }

    private func proxyRequest(to targetURL: URL, connection: NWConnection) {
        var request = URLRequest(url: targetURL)
        request.httpMethod = "GET"

        // Apply spoofed headers based on the target domain
        for (key, value) in Self.spoofHeaders(for: targetURL) {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                print("[HLSProxy] Request failed for \(targetURL.lastPathComponent): \(error.localizedDescription)")
                self.sendError(connection: connection, code: 502, message: "Bad Gateway")
                return
            }

            guard let httpResponse = response as? HTTPURLResponse,
                  let data = data else {
                self.sendError(connection: connection, code: 502, message: "Bad Gateway")
                return
            }

            // If this is an m3u8 playlist, rewrite segment URLs to go through our proxy
            var responseData = data
            if targetURL.pathExtension.lowercased() == "m3u8" ||
               (httpResponse.mimeType?.contains("mpegurl") == true) {
                responseData = self.rewritePlaylist(data: data, baseURL: targetURL)
            }

            // Build HTTP response
            var responseHeaders = "HTTP/1.1 \(httpResponse.statusCode) OK\r\n"
            responseHeaders += "Content-Length: \(responseData.count)\r\n"
            responseHeaders += "Access-Control-Allow-Origin: *\r\n"
            responseHeaders += "Access-Control-Allow-Headers: *\r\n"

            if let contentType = httpResponse.mimeType {
                responseHeaders += "Content-Type: \(contentType)\r\n"
            }

            // Forward cache-control headers
            if let cacheControl = httpResponse.value(forHTTPHeaderField: "Cache-Control") {
                responseHeaders += "Cache-Control: \(cacheControl)\r\n"
            }

            responseHeaders += "\r\n"

            var fullResponse = Data(responseHeaders.utf8)
            fullResponse.append(responseData)

            connection.send(content: fullResponse, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
        task.resume()
    }

    /// Rewrite m3u8 playlist to route segment URLs through the proxy
    private func rewritePlaylist(data: Data, baseURL: URL) -> Data {
        guard let content = String(data: data, encoding: .utf8) else { return data }

        let lines = content.components(separatedBy: "\n")
        var rewritten: [String] = []
        let baseStr = baseURL.deletingLastPathComponent().absoluteString

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                rewritten.append(line)
                continue
            }

            // This is a URL line (segment or sub-playlist)
            let absoluteURL: String
            if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
                absoluteURL = trimmed
            } else {
                // Relative URL — resolve against base
                absoluteURL = baseStr + trimmed
            }

            // Rewrite to go through our proxy
            let currentPort = self.port
            let encoded = absoluteURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? absoluteURL
            rewritten.append("http://127.0.0.1:\(currentPort)/proxy?url=\(encoded)")
        }

        return Data(rewritten.joined(separator: "\n").utf8)
    }

    // MARK: - Error Response

    private func sendError(connection: NWConnection, code: Int, message: String) {
        let body = "{\"error\": \"\(message)\"}"
        let response = "HTTP/1.1 \(code) \(message)\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nAccess-Control-Allow-Origin: *\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    /// The liveness answer. Deliberately trivial and uncached — the only thing it proves is that this
    /// port is still bound to a listener in this process, which is precisely the thing `isRunning`
    /// cannot promise after a suspend.
    private func sendHealth(connection: NWConnection) {
        let body = "{\"ok\": true}"
        let response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nCache-Control: no-store\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

// MARK: - Offline Downloads

/// Which HLS variant to pull down when a stream offers several.
public enum DownloadQuality: String, Codable, Sendable, CaseIterable, Identifiable {
    case best
    case standard
    case saver

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .best: return "Best quality"
        case .standard: return "Balanced"
        case .saver: return "Data saver"
        }
    }

    public var detail: String {
        switch self {
        case .best: return "Highest resolution, largest file"
        case .standard: return "Middle resolution"
        case .saver: return "Lowest resolution, smallest file"
        }
    }

    public var icon: String {
        switch self {
        case .best: return "sparkles"
        case .standard: return "slider.horizontal.3"
        case .saver: return "arrow.down.circle"
        }
    }
}

public enum VideoDownloadState: String, Codable, Sendable {
    case queued
    case downloading
    case paused
    case completed
    case failed
}

/// One class stored offline, plus its download progress.
public struct DownloadedVideo: Identifiable, Codable, Hashable, Sendable {
    public var video: RecordedVideo
    public var state: VideoDownloadState
    public var quality: DownloadQuality
    public var resolution: String?
    public var completedSegments: Int
    public var totalSegments: Int
    public var bytesOnDisk: Int64
    public var createdAt: Date
    public var errorMessage: String?

    public var id: String { video.id }

    public var progress: Double {
        if state == .completed { return 1 }
        guard totalSegments > 0 else { return 0 }
        return min(1, Double(completedSegments) / Double(totalSegments))
    }

    public var isActive: Bool { state == .queued || state == .downloading }

    public var formattedSize: String {
        guard bytesOnDisk > 0 else { return "—" }
        return ByteCountFormatter.string(fromByteCount: bytesOnDisk, countStyle: .file)
    }

    public var statusLabel: String {
        switch state {
        case .queued:
            return "Waiting to download"
        case .downloading:
            return totalSegments > 0 ? "Downloading · \(Int(progress * 100))%" : "Preparing…"
        case .paused:
            return totalSegments > 0 ? "Paused · \(Int(progress * 100))%" : "Paused"
        case .completed:
            return [resolution, formattedSize].compactMap { $0 }.joined(separator: " · ")
        case .failed:
            return errorMessage ?? "Download failed"
        }
    }
}

public enum VideoDownloadError: LocalizedError {
    case invalidURL
    case noVariants
    case emptyPlaylist
    case server(Int)
    case emptyResponse

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "This class has no valid stream URL."
        case .noVariants: return "No downloadable quality was found."
        case .emptyPlaylist: return "The stream listed no video segments."
        case .server(let code): return "The server refused the download (HTTP \(code))."
        case .emptyResponse: return "A video segment came back empty."
        }
    }
}

/// Pulls an HLS class down segment by segment and rewrites its playlist to point at
/// the local files, so `AVPlayer` can play it back with no network at all.
///
/// Everything stays inside the app container — nothing is exported to Files or Photos.
@MainActor
public final class VideoDownloadStore: ObservableObject {
    public static let shared = VideoDownloadStore()

    /// Keyed by `RecordedVideo.id`.
    @Published public private(set) var items: [String: DownloadedVideo] = [:]

    /// `nonisolated` so the disk-side helpers below can read them without hopping actors.
    /// `playlistFileName` is public because `MedxOfflineScheme.assetURL` defaults to it.
    nonisolated public static let playlistFileName = "local.m3u8"
    /// Only written when the chosen variant carries its audio in a separate rendition —
    /// then `local.m3u8` becomes a master playlist tying these two together.
    nonisolated fileprivate static let videoPlaylistFileName = "video.m3u8"
    nonisolated fileprivate static let audioPlaylistFileName = "audio.m3u8"
    nonisolated fileprivate static let metaFileName = "meta.json"
    nonisolated private static let maxConcurrentSegments = 4
    nonisolated private static let maxConcurrentDownloads = 2

    private let fileManager = FileManager.default
    private var tasks: [String: Task<Void, Never>] = [:]
    private var generation: [String: Int] = [:]

    private init() {
        loadFromDisk()
        observeLiveActivityIntents()
    }

    /// The Pause / Resume / Cancel buttons inside the download Live Activity.
    ///
    /// A `LiveActivityIntent` runs in this process but is *declared* in
    /// `MedxSharedIntents.swift`, which is compiled into the widget extension too and therefore
    /// cannot see this type. So the intents post a notification and the decision about what pausing
    /// means stays here, where the downloader is.
    private func observeLiveActivityIntents() {
        observe(.medxDownloadPauseRequested) { $0.pause($1) }
        observe(.medxDownloadResumeRequested) { $0.resume($1) }
        observe(.medxDownloadCancelRequested) { $0.remove($1) }
    }

    private func observe(
        _ name: Notification.Name,
        _ action: @escaping @MainActor (VideoDownloadStore, String) -> Void
    ) {
        NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { note in
            guard let id = note.userInfo?[MedxDownloadIntentKey.videoId] as? String else { return }
            Task { @MainActor in action(VideoDownloadStore.shared, id) }
        }
    }

    // MARK: - Locations

    nonisolated static func rootDirectory() -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var folder = base.appendingPathComponent("OfflineVideos", isDirectory: true)
        if !fm.fileExists(atPath: folder.path) {
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? folder.setResourceValues(values)
        }
        return folder
    }

    nonisolated static func folderName(for videoId: String) -> String {
        let cleaned = videoId
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        return cleaned.isEmpty ? "unknown" : cleaned
    }

    nonisolated static func directory(for videoId: String) -> URL {
        rootDirectory().appendingPathComponent(folderName(for: videoId), isDirectory: true)
    }

    /// Nonisolated on purpose: the player asks for this while building its asset.
    /// Returns nil unless a *finished* download exists on disk.
    ///
    /// This is a `file://` URL and is only good for existence checks — AVFoundation cannot
    /// load an HLS playlist from the file system, so playback goes through
    /// `MedxOfflineScheme.assetURL(videoId:)` and `MedxOfflineAssetLoader` instead.
    public nonisolated static func offlinePlaylistURL(for videoId: String) -> URL? {
        let dir = directory(for: videoId)
        let playlist = dir.appendingPathComponent(playlistFileName)
        guard FileManager.default.fileExists(atPath: playlist.path) else { return nil }
        guard let data = try? Data(contentsOf: dir.appendingPathComponent(metaFileName)),
              let item = try? JSONDecoder().decode(DownloadedVideo.self, from: data),
              item.state == .completed else { return nil }
        return playlist
    }

    /// True when a finished download is sitting on disk, whatever the in-memory state says.
    public nonisolated static func hasOfflineCopy(_ videoId: String) -> Bool {
        offlinePlaylistURL(for: videoId) != nil
    }

    // MARK: - Read models

    public var allItems: [DownloadedVideo] {
        items.values.sorted { $0.createdAt > $1.createdAt }
    }

    public var inProgressItems: [DownloadedVideo] {
        allItems.filter { $0.state != .completed }
    }

    public var completedItems: [DownloadedVideo] {
        allItems.filter { $0.state == .completed }
    }

    public var activeCount: Int {
        items.values.filter { $0.isActive }.count
    }

    public var totalBytes: Int64 {
        items.values.reduce(0) { $0 + $1.bytesOnDisk }
    }

    public var formattedTotalSize: String {
        guard totalBytes > 0 else { return "0 KB" }
        return ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    public func item(for videoId: String) -> DownloadedVideo? {
        items[videoId]
    }

    public func isDownloaded(_ videoId: String) -> Bool {
        items[videoId]?.state == .completed
    }

    // MARK: - Commands

    public func start(_ video: RecordedVideo, quality: DownloadQuality = .best) {
        if let existing = items[video.id], existing.state == .completed || existing.isActive { return }

        var item = items[video.id] ?? DownloadedVideo(
            video: video,
            state: .queued,
            quality: quality,
            resolution: nil,
            completedSegments: 0,
            totalSegments: 0,
            bytesOnDisk: 0,
            createdAt: Date(),
            errorMessage: nil
        )
        item.video = video
        item.state = .queued
        item.quality = quality
        item.errorMessage = nil

        // A class with no stream URL used to no-op silently, which read as "download
        // does nothing". Surface it as a failed row instead.
        if video.streamUrl.isEmpty {
            item.state = .failed
            item.errorMessage = VideoDownloadError.invalidURL.errorDescription
            items[video.id] = item
            persist(video.id)
            return
        }

        items[video.id] = item

        persist(video.id)
        pump()
    }

    public func startAll(_ videos: [RecordedVideo], quality: DownloadQuality = .standard) {
        for video in videos where items[video.id]?.state != .completed {
            start(video, quality: quality)
        }
    }

    public func pause(_ videoId: String) {
        tasks[videoId]?.cancel()
        tasks[videoId] = nil
        update(videoId) { if $0.state != .completed { $0.state = .paused } }
        persist(videoId)
        // The activity *stays*, flipped to its paused face. Ending it here is what the first
        // version did, and it meant pausing from the Lock Screen removed the only place Resume
        // could be pressed — the whole point of the buttons.
        MedxLiveActivityController.shared.updateDownload(
            id: videoId,
            completed: items[videoId]?.completedSegments ?? 0,
            total: items[videoId]?.totalSegments ?? 0,
            statusText: "Paused",
            isPaused: true
        )
        pump()
    }

    /// Also used to retry a failed download — everything already on disk is kept.
    public func resume(_ videoId: String) {
        guard let item = items[videoId], item.state != .completed, !item.isActive else { return }
        update(videoId) {
            $0.state = .queued
            $0.errorMessage = nil
        }
        persist(videoId)
        MedxLiveActivityController.shared.updateDownload(
            id: videoId,
            completed: item.completedSegments,
            total: item.totalSegments,
            statusText: "Queued",
            isPaused: false
        )
        pump()
    }

    public func remove(_ videoId: String) {
        tasks[videoId]?.cancel()
        tasks[videoId] = nil
        generation[videoId] = (generation[videoId] ?? 0) + 1
        endDownloadActivity(videoId, statusText: "Removed")
        items[videoId] = nil

        let dir = Self.directory(for: videoId)
        Task.detached(priority: .utility) {
            // Give any in-flight segment write a moment to fail out first.
            try? await Task.sleep(nanoseconds: 250_000_000)
            try? FileManager.default.removeItem(at: dir)
        }
        pump()
    }

    /// Closes out a Live Activity for a download that is no longer running.
    private func endDownloadActivity(_ videoId: String, statusText: String) {
        MedxLiveActivityController.shared.endDownload(
            id: videoId,
            completed: items[videoId]?.completedSegments ?? 0,
            total: items[videoId]?.totalSegments ?? 0,
            statusText: statusText,
            finished: false
        )
    }

    public func removeAll() {
        for videoId in Array(items.keys) {
            remove(videoId)
        }
    }

    // MARK: - Queue

    /// Keeps at most `maxConcurrentDownloads` classes downloading at once; the rest wait.
    private func pump() {
        guard tasks.count < Self.maxConcurrentDownloads else { return }
        let waiting = items.values
            .filter { $0.state == .queued && tasks[$0.id] == nil }
            .sorted { $0.createdAt < $1.createdAt }
        for item in waiting.prefix(Self.maxConcurrentDownloads - tasks.count) {
            launch(item.video, quality: item.quality)
        }
    }

    private func launch(_ video: RecordedVideo, quality: DownloadQuality) {
        let id = video.id
        let gen = (generation[id] ?? 0) + 1
        generation[id] = gen
        tasks[id] = Task { [weak self] in
            await self?.run(video: video, quality: quality, generation: gen)
        }
    }

    private func run(video: RecordedVideo, quality: DownloadQuality, generation gen: Int) async {
        let id = video.id
        let dir = Self.directory(for: id)

        do {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            update(id) { $0.state = .downloading }

            let plan = try await Self.buildPlan(streamUrl: video.streamUrl, quality: quality)
            for playlist in plan.playlists {
                try await Self.write(text: playlist.text, to: dir.appendingPathComponent(playlist.name))
            }

            let pending = await Self.missingResources(plan.resources, in: dir)
            update(id) {
                $0.totalSegments = plan.resources.count
                $0.completedSegments = plan.resources.count - pending.count
                $0.resolution = plan.resolution
            }
            persist(id)

            // Only now is the segment count known, so this is the earliest point a Live
            // Activity can show real progress rather than an indeterminate spinner.
            MedxLiveActivityController.shared.startDownload(
                id: id,
                title: video.title,
                subject: video.subject,
                totalSegments: plan.resources.count
            )

            try await downloadResources(pending, into: dir, id: id)
            try Task.checkCancellation()

            let size = await Self.directorySize(at: dir)
            update(id) {
                $0.state = .completed
                $0.completedSegments = $0.totalSegments
                $0.bytesOnDisk = size
                $0.errorMessage = nil
            }
            persist(id)
            MedxLiveActivityController.shared.endDownload(
                id: id,
                completed: items[id]?.totalSegments ?? 0,
                total: items[id]?.totalSegments ?? 0,
                statusText: "Saved · \(items[id]?.formattedSize ?? "")",
                finished: true
            )
            HapticManager.success()
        } catch {
            let wasCancelled = Task.isCancelled
                || error is CancellationError
                || (error as? URLError)?.code == .cancelled
            update(id) {
                guard $0.state != .completed else { return }
                if wasCancelled {
                    $0.state = .paused
                } else {
                    $0.state = .failed
                    $0.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
            persist(id)
            MedxLiveActivityController.shared.endDownload(
                id: id,
                completed: items[id]?.completedSegments ?? 0,
                total: items[id]?.totalSegments ?? 0,
                statusText: items[id]?.statusLabel ?? "Stopped",
                finished: false
            )
        }

        if generation[id] == gen {
            tasks[id] = nil
        }
        pump()
    }

    private func downloadResources(_ resources: [DownloadResource], into directory: URL, id: String) async throws {
        guard !resources.isEmpty else { return }
        var next = 0
        var sinceLastPersist = 0

        try await withThrowingTaskGroup(of: Int64.self) { group in
            while next < resources.count, next < Self.maxConcurrentSegments {
                let resource = resources[next]
                group.addTask { try await Self.downloadResource(resource, into: directory) }
                next += 1
            }

            while let bytes = try await group.next() {
                try Task.checkCancellation()
                update(id) {
                    $0.completedSegments = min($0.completedSegments + 1, max($0.totalSegments, 1))
                    $0.bytesOnDisk += bytes
                }
                sinceLastPersist += 1
                if sinceLastPersist >= 12 {
                    sinceLastPersist = 0
                    persist(id)
                }
                // The Lock Screen is refreshed on the same beat as the on-disk manifest;
                // pushing an update per segment would be hundreds of writes for one class.
                if sinceLastPersist == 0, let item = items[id] {
                    MedxLiveActivityController.shared.updateDownload(
                        id: id,
                        completed: item.completedSegments,
                        total: item.totalSegments,
                        statusText: item.statusLabel
                    )
                }
                if next < resources.count {
                    let resource = resources[next]
                    group.addTask { try await Self.downloadResource(resource, into: directory) }
                    next += 1
                }
            }
        }
    }

    // MARK: - Bookkeeping

    private func update(_ videoId: String, _ mutate: (inout DownloadedVideo) -> Void) {
        guard var item = items[videoId] else { return }
        mutate(&item)
        items[videoId] = item
    }

    private func persist(_ videoId: String) {
        guard let item = items[videoId] else { return }
        let dir = Self.directory(for: videoId)
        Task.detached(priority: .utility) {
            let fm = FileManager.default
            if !fm.fileExists(atPath: dir.path) {
                try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            guard let data = try? JSONEncoder().encode(item) else { return }
            try? data.write(to: dir.appendingPathComponent(Self.metaFileName), options: .atomic)
        }
    }

    private func loadFromDisk() {
        let root = Self.rootDirectory()
        guard let entries = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }

        var loaded: [String: DownloadedVideo] = [:]
        for entry in entries {
            guard let data = try? Data(contentsOf: entry.appendingPathComponent(Self.metaFileName)),
                  var item = try? JSONDecoder().decode(DownloadedVideo.self, from: data) else {
                // No readable manifest: drop the folder so orphaned bytes don't linger.
                try? fileManager.removeItem(at: entry)
                continue
            }
            // A download can't survive a relaunch mid-flight — surface it as resumable.
            if item.isActive {
                item.state = .paused
            }
            loaded[item.id] = item
        }
        items = loaded
    }

    // MARK: - Playlist planning

    fileprivate struct DownloadResource: Sendable {
        let url: URL
        let filename: String
    }

    fileprivate struct PlaylistFile: Sendable {
        let name: String
        let text: String
    }

    fileprivate struct DownloadPlan: Sendable {
        /// One entry when the variant is muxed; three (master + video + audio) when the
        /// stream keeps its audio in a separate rendition.
        let playlists: [PlaylistFile]
        let resources: [DownloadResource]
        let resolution: String?
    }

    private struct PlaylistVariant: Sendable {
        let url: URL
        let bandwidth: Int
        let resolution: String?
        let audioGroup: String?
    }

    /// Collects every remote file a playlist needs and hands out the flat local name each
    /// one is saved under. Shared across the video and audio playlists of one download so
    /// two renditions can never claim the same filename.
    private struct ResourceNamer {
        var resources: [DownloadResource] = []
        private var nameByURL: [String: String] = [:]
        private var counter = 0

        mutating func localName(for url: URL, kind: String, fallbackExtension: String) -> String {
            if let existing = nameByURL[url.absoluteString] { return existing }
            counter += 1
            var ext = url.pathExtension.lowercased()
            if ext.isEmpty { ext = fallbackExtension }
            let name = String(format: "%@%05d.%@", kind, counter, ext)
            nameByURL[url.absoluteString] = name
            resources.append(DownloadResource(url: url, filename: name))
            return name
        }
    }

    /// Fetches the master playlist, picks a variant, then rewrites the media playlist so
    /// every segment / key / init-section points at a plain filename next to it on disk.
    nonisolated fileprivate static func buildPlan(streamUrl: String, quality: DownloadQuality) async throws -> DownloadPlan {
        guard let masterURL = URL(string: streamUrl) else { throw VideoDownloadError.invalidURL }

        let masterText = try await fetchText(masterURL)
        var namer = ResourceNamer()

        guard masterText.contains("#EXT-X-STREAM-INF") else {
            // Already a media playlist — nothing to choose.
            let media = try rewriteMediaPlaylist(masterText, baseURL: masterURL, kind: "seg", namer: &namer)
            return DownloadPlan(
                playlists: [PlaylistFile(name: playlistFileName, text: media)],
                resources: namer.resources,
                resolution: nil
            )
        }

        let variants = parseVariants(playlist: masterText, baseURL: masterURL)
        guard !variants.isEmpty else { throw VideoDownloadError.noVariants }
        let chosen: PlaylistVariant
        switch quality {
        case .saver: chosen = variants[0]
        case .standard: chosen = variants[variants.count / 2]
        case .best: chosen = variants[variants.count - 1]
        }

        let videoText = try await fetchText(chosen.url)
        let videoPlaylist = try rewriteMediaPlaylist(videoText, baseURL: chosen.url, kind: "seg", namer: &namer)

        // A variant whose audio lives in its own rendition would download silent without
        // this — the audio segments are listed in a playlist of their own.
        if let audioURL = audioRenditionURL(for: chosen, playlist: masterText, baseURL: masterURL),
           audioURL != chosen.url {
            let audioText = try await fetchText(audioURL)
            let audioPlaylist = try rewriteMediaPlaylist(audioText, baseURL: audioURL, kind: "aud", namer: &namer)
            return DownloadPlan(
                playlists: [
                    PlaylistFile(
                        name: playlistFileName,
                        text: localMasterPlaylist(bandwidth: chosen.bandwidth, resolution: chosen.resolution)
                    ),
                    PlaylistFile(name: videoPlaylistFileName, text: videoPlaylist),
                    PlaylistFile(name: audioPlaylistFileName, text: audioPlaylist)
                ],
                resources: namer.resources,
                resolution: chosen.resolution
            )
        }

        return DownloadPlan(
            playlists: [PlaylistFile(name: playlistFileName, text: videoPlaylist)],
            resources: namer.resources,
            resolution: chosen.resolution
        )
    }

    /// Rewrites one media playlist in place: absolute segment/key/init URLs become plain
    /// sibling filenames, and the result is closed off with `#EXT-X-ENDLIST`.
    nonisolated private static func rewriteMediaPlaylist(
        _ text: String,
        baseURL: URL,
        kind: String,
        namer: inout ResourceNamer
    ) throws -> String {
        var lines: [String] = []
        var sawEndList = false
        let resourcesBefore = namer.resources.count

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasPrefix("#") {
                if line.hasPrefix("#EXT-X-ENDLIST") { sawEndList = true }

                let isMap = line.hasPrefix("#EXT-X-MAP")
                let isKey = line.hasPrefix("#EXT-X-KEY") || line.hasPrefix("#EXT-X-SESSION-KEY")
                if isMap || isKey,
                   let uri = quotedAttribute("URI", in: line),
                   !uri.isEmpty,
                   let resolved = URL(string: uri, relativeTo: baseURL)?.absoluteURL {
                    let name = namer.localName(
                        for: resolved,
                        kind: isMap ? "\(kind)-init" : "key",
                        fallbackExtension: isMap ? "mp4" : "key"
                    )
                    lines.append(line.replacingOccurrences(of: "URI=\"\(uri)\"", with: "URI=\"\(name)\""))
                    continue
                }

                lines.append(line)
                continue
            }

            guard let resolved = URL(string: line, relativeTo: baseURL)?.absoluteURL else { continue }
            lines.append(namer.localName(for: resolved, kind: kind, fallbackExtension: "ts"))
        }

        guard namer.resources.count > resourcesBefore else { throw VideoDownloadError.emptyPlaylist }
        // Without ENDLIST AVPlayer treats the local file as a live stream and keeps polling.
        if !sawEndList { lines.append("#EXT-X-ENDLIST") }

        return lines.joined(separator: "\n") + "\n"
    }

    /// The two-rendition master that `local.m3u8` becomes when audio is downloaded separately.
    nonisolated private static func localMasterPlaylist(bandwidth: Int, resolution: String?) -> String {
        var lines = [
            "#EXTM3U",
            "#EXT-X-VERSION:4",
            "#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"offline-audio\",NAME=\"Audio\","
                + "DEFAULT=YES,AUTOSELECT=YES,URI=\"\(audioPlaylistFileName)\""
        ]

        var streamInf = "#EXT-X-STREAM-INF:BANDWIDTH=\(bandwidth > 0 ? bandwidth : 2_000_000)"
        if let resolution, !resolution.isEmpty {
            streamInf += ",RESOLUTION=\(resolution)"
        }
        streamInf += ",AUDIO=\"offline-audio\""
        lines.append(streamInf)
        lines.append(videoPlaylistFileName)

        return lines.joined(separator: "\n") + "\n"
    }

    /// Finds the default audio rendition for a variant's `AUDIO` group. Renditions with no
    /// `URI` mean the audio is muxed into the video segments, so there is nothing extra
    /// to fetch.
    nonisolated private static func audioRenditionURL(
        for variant: PlaylistVariant,
        playlist: String,
        baseURL: URL
    ) -> URL? {
        guard let group = variant.audioGroup else { return nil }

        var fallback: URL?
        for rawLine in playlist.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("#EXT-X-MEDIA"),
                  plainAttribute("TYPE", in: line) == "AUDIO",
                  quotedAttribute("GROUP-ID", in: line) == group,
                  let uri = quotedAttribute("URI", in: line), !uri.isEmpty,
                  let resolved = URL(string: uri, relativeTo: baseURL)?.absoluteURL else { continue }

            if plainAttribute("DEFAULT", in: line) == "YES" { return resolved }
            if fallback == nil { fallback = resolved }
        }
        return fallback
    }

    nonisolated private static func parseVariants(playlist: String, baseURL: URL) -> [PlaylistVariant] {
        var variants: [PlaylistVariant] = []
        var pendingInfo: String?

        for rawLine in playlist.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("#EXT-X-STREAM-INF") {
                pendingInfo = line
                continue
            }
            if line.hasPrefix("#") { continue }
            guard let info = pendingInfo else { continue }
            pendingInfo = nil
            guard let url = URL(string: line, relativeTo: baseURL)?.absoluteURL else { continue }
            variants.append(
                PlaylistVariant(
                    url: url,
                    bandwidth: Int(plainAttribute("BANDWIDTH", in: info) ?? "") ?? 0,
                    resolution: plainAttribute("RESOLUTION", in: info),
                    audioGroup: quotedAttribute("AUDIO", in: info)
                )
            )
        }

        return variants.sorted { $0.bandwidth < $1.bandwidth }
    }

    nonisolated private static func quotedAttribute(_ name: String, in line: String) -> String? {
        guard let range = line.range(of: "\(name)=\"") else { return nil }
        let rest = line[range.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<end])
    }

    /// Unquoted attribute (`BANDWIDTH=1234`). The leading delimiter keeps `BANDWIDTH`
    /// from matching inside `AVERAGE-BANDWIDTH`.
    nonisolated private static func plainAttribute(_ name: String, in line: String) -> String? {
        for delimiter in [":", ","] {
            guard let range = line.range(of: "\(delimiter)\(name)=") else { continue }
            var value = ""
            var index = range.upperBound
            while index < line.endIndex, line[index] != "," {
                value.append(line[index])
                index = line.index(after: index)
            }
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    // MARK: - Transfer

    nonisolated private static func fetchText(_ url: URL) async throws -> String {
        let data = try await fetchData(url)
        guard let text = String(data: data, encoding: .utf8) else { throw VideoDownloadError.emptyResponse }
        return text
    }

    nonisolated private static func fetchData(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 45
        for (key, value) in HLSProxyServer.spoofHeaders(for: url) {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw VideoDownloadError.server(http.statusCode)
        }
        return data
    }

    nonisolated private static func downloadResource(_ resource: DownloadResource, into directory: URL) async throws -> Int64 {
        let destination = directory.appendingPathComponent(resource.filename)
        if let attributes = try? FileManager.default.attributesOfItem(atPath: destination.path),
           let size = attributes[.size] as? NSNumber,
           size.int64Value > 0 {
            return 0
        }

        let data = try await fetchData(resource.url)
        guard !data.isEmpty else { throw VideoDownloadError.emptyResponse }
        try data.write(to: destination, options: .atomic)
        return Int64(data.count)
    }

    nonisolated private static func missingResources(_ resources: [DownloadResource], in directory: URL) async -> [DownloadResource] {
        let fm = FileManager.default
        return resources.filter { resource in
            let path = directory.appendingPathComponent(resource.filename).path
            guard let attributes = try? fm.attributesOfItem(atPath: path),
                  let size = attributes[.size] as? NSNumber else { return true }
            return size.int64Value <= 0
        }
    }

    nonisolated private static func write(text: String, to url: URL) async throws {
        try Data(text.utf8).write(to: url, options: .atomic)
    }

    nonisolated private static func directorySize(at directory: URL) async -> Int64 {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }

        var total: Int64 = 0
        for url in contents {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey])
            total += Int64(values?.fileSize ?? 0)
        }
        return total
    }
}


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
    private static let spoofedHeaders: [String: String] = [
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
    private static let apiHeaders: [String: String] = [
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
    public func start() {
        if isRunning { return }

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
                    case .cancelled:
                        self.isRunning = false
                        self.port = 0
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

    /// Stop the proxy server
    public func stop() {
        listener?.cancel()
        listener = nil
        DispatchQueue.main.async {
            self.isRunning = false
            self.port = 0
        }
    }

    /// Convert a remote stream URL to a local proxied URL
    public func proxiedURL(for remoteURL: String) -> URL? {
        guard isRunning, port > 0 else { return nil }
        let encoded = remoteURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? remoteURL
        return URL(string: "http://127.0.0.1:\(port)/proxy?url=\(encoded)")
    }

    /// Generate a playback session ID (mimics iOS native behavior)
    private func generateSessionId() -> String {
        UUID().uuidString
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

            let path = parts[1]

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
        let host = targetURL.host ?? ""
        let pathExt = targetURL.pathExtension.lowercased()

        if host.contains("liveplayback") || pathExt == "ts" || pathExt == "m3u8" {
            // HLS streaming headers
            for (key, value) in Self.spoofedHeaders {
                request.setValue(value, forHTTPHeaderField: key)
            }
            request.setValue(host, forHTTPHeaderField: "Host")
            request.setValue(generateSessionId(), forHTTPHeaderField: "X-Playback-Session-Id")
        } else if host.contains("arisemedicalacademy") {
            // API headers
            for (key, value) in Self.apiHeaders {
                request.setValue(value, forHTTPHeaderField: key)
            }
            request.setValue(host, forHTTPHeaderField: "Host")
        } else if host.contains("cloudfront") {
            // CDN headers
            request.setValue(Self.spoofedHeaders["User-Agent"], forHTTPHeaderField: "User-Agent")
            request.setValue(host, forHTTPHeaderField: "Host")
            request.setValue("cross-site", forHTTPHeaderField: "Sec-Fetch-Site")
            request.setValue("no-cors", forHTTPHeaderField: "Sec-Fetch-Mode")
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
}

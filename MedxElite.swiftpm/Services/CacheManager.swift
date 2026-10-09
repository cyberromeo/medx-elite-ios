import Foundation

/// Fast on-disk and in-memory cache manager for offline module access and response caching
public actor CacheManager {
    public static let shared = CacheManager()

    private let fileManager = FileManager.default
    private let cacheDir: URL
    private var memoryCache = NSCache<NSString, NSData>()

    /// When each key was last written in this process. Disk entries from an earlier launch fall
    /// back to the file's modification date.
    private var writtenAt: [String: Date] = [:]

    /// Anything written before this moment is stale: it is still served when the network fails,
    /// but it no longer short-circuits a fetch. Starts at launch, so the first read of every
    /// collection in a session goes to the backend, and moves forward on pull-to-refresh and on
    /// returning to the app.
    private var staleBefore = Date()

    private init() {
        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        let root = paths[0].appendingPathComponent("MedxEliteCache", isDirectory: true)
        if !fileManager.fileExists(atPath: root.path) {
            try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        }
        self.cacheDir = root
        memoryCache.countLimit = 100
        memoryCache.totalCostLimit = 50 * 1024 * 1024 // 50 MB RAM cache
    }

    public func set<T: Encodable>(_ object: T, forKey key: String) {
        guard let data = try? JSONEncoder().encode(object) else { return }
        memoryCache.setObject(data as NSData, forKey: key as NSString, cost: data.count)
        writtenAt[key] = Date()
        let fileUrl = cacheDir.appendingPathComponent(sanitizedKey(key))
        try? data.write(to: fileUrl, options: .atomic)
    }

    /// Whether `key` may be served without asking the backend: written after the last
    /// `markAllStale()` (or after launch) and less than `maxAge` ago.
    ///
    /// This is the fix for "new content does not appear until I clear the cache". Every read used
    /// to return the cached copy whenever one existed, with no age at all — so a module, paper or
    /// class added on the backend stayed invisible until the cache was deleted by hand.
    public func isFresh(forKey key: String, maxAge: TimeInterval, sinceLaunch: Bool = true) -> Bool {
        let stamp: Date
        if let written = writtenAt[key] {
            stamp = written
        } else {
            let fileUrl = cacheDir.appendingPathComponent(sanitizedKey(key))
            guard let attributes = try? fileManager.attributesOfItem(atPath: fileUrl.path),
                  let modified = attributes[.modificationDate] as? Date
            else { return false }
            stamp = modified
        }
        if sinceLaunch, stamp < staleBefore { return false }
        return Date().timeIntervalSince(stamp) < maxAge
    }

    /// Marks everything cached so far as stale without deleting it. The next read of each key
    /// goes to the backend first and falls back to the cached copy only if that fails, so
    /// offline still works.
    public func markAllStale() {
        staleBefore = Date()
    }

    public func get<T: Decodable>(forKey key: String, as type: T.Type) -> T? {
        if let memData = memoryCache.object(forKey: key as NSString) {
            if let obj = try? JSONDecoder().decode(type, from: memData as Data) {
                return obj
            }
        }
        let fileUrl = cacheDir.appendingPathComponent(sanitizedKey(key))
        guard let diskData = try? Data(contentsOf: fileUrl) else { return nil }
        memoryCache.setObject(diskData as NSData, forKey: key as NSString, cost: diskData.count)
        return try? JSONDecoder().decode(type, from: diskData)
    }

    public func clearAll() {
        memoryCache.removeAllObjects()
        writtenAt.removeAll()
        try? fileManager.removeItem(at: cacheDir)
        try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    /// Drops one cached entry, in both memory and on disk.
    ///
    /// The one write that needs this is a VOD import: it adds a document to `medx_videos`, and
    /// the Classes tab reads that collection through the cache — so without dropping `col_medx_videos`
    /// the freshly filed class would not appear until the cache aged out or the app relaunched.
    public func remove(forKey key: String) {
        memoryCache.removeObject(forKey: key as NSString)
        writtenAt[key] = nil
        let fileUrl = cacheDir.appendingPathComponent(sanitizedKey(key))
        try? fileManager.removeItem(at: fileUrl)
    }

    /// Total bytes the cached JSON payloads currently occupy on disk.
    public func diskSize() -> Int64 {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: cacheDir,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }

        var total: Int64 = 0
        for url in contents {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey])
            total += Int64(values?.fileSize ?? 0)
        }
        return total
    }

    /// Bumped whenever the decoding rules change. Firestore payloads cached by an older
    /// build can hold values that the current models would reject (or, worse, an empty
    /// array left behind by a decode that used to fail), so the whole namespace is
    /// abandoned rather than migrated.
    private static let schemaVersion = "v2"

    private func sanitizedKey(_ key: String) -> String {
        Self.schemaVersion + "_" + key.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "?", with: "_")
            .replacingOccurrences(of: "&", with: "_") + ".json"
    }

    /// Removes cache files written by an earlier schema version. Cheap enough to run at
    /// launch and it keeps `diskSize()` honest.
    public func pruneStaleVersions() {
        guard let contents = try? fileManager.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil) else {
            return
        }
        for url in contents where !url.lastPathComponent.hasPrefix(Self.schemaVersion + "_") {
            try? fileManager.removeItem(at: url)
        }
    }
}

public extension Notification.Name {
    /// Posted when the app comes back after a while away. Screens that show backend content
    /// refetch on it, so what is on screen catches up without a pull or a relaunch.
    static let medxContentShouldRefresh = Notification.Name("medx.content.shouldRefresh")
}

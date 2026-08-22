import Foundation

/// Fast on-disk and in-memory cache manager for offline module access and response caching
public actor CacheManager {
    public static let shared = CacheManager()

    private let fileManager = FileManager.default
    private let cacheDir: URL
    private var memoryCache = NSCache<NSString, NSData>()

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
        let fileUrl = cacheDir.appendingPathComponent(sanitizedKey(key))
        try? data.write(to: fileUrl, options: .atomic)
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
        try? fileManager.removeItem(at: cacheDir)
        try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
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

    private func sanitizedKey(_ key: String) -> String {
        key.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "?", with: "_")
            .replacingOccurrences(of: "&", with: "_") + ".json"
    }
}

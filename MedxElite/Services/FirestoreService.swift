import Foundation

public actor FirestoreService {
    public static let shared = FirestoreService()

    private let cache = CacheManager.shared

    private init() {}

    // MARK: - Generic Document Fetching & Parsing

    public func fetchCollection<T: Codable>(
        collection: String,
        idToken: String,
        useCache: Bool = true
    ) async throws -> [T] {
        let cacheKey = "col_\(collection)"
        // An empty cached array is treated as a miss. A single bad decode used to poison
        // the cache with `[]` and the screen stayed blank until the app was reinstalled.
        if useCache, let cached: [T] = await cache.get(forKey: cacheKey, as: [T].self), !cached.isEmpty {
            return cached
        }

        var decodedItems: [T] = []
        var pageToken: String?
        var pagesFetched = 0

        repeat {
            var components = "\(FirebaseConfig.firestoreRestBase)/\(collection)?pageSize=300"
            if let pageToken, let encoded = pageToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                components += "&pageToken=\(encoded)"
            }
            guard let url = URL(string: components) else { throw URLError(.badURL) }

            var request = URLRequest(url: url)
            request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                if let cached: [T] = await cache.get(forKey: cacheKey, as: [T].self), !cached.isEmpty {
                    return cached
                }
                throw URLError(.badServerResponse)
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw URLError(.cannotParseResponse)
            }

            decodedItems.append(contentsOf: Self.decodeDocuments(json["documents"] as? [[String: Any]] ?? []) as [T])
            pageToken = json["nextPageToken"] as? String
            pagesFetched += 1
            // A guard against a server that keeps handing back the same token.
        } while (pageToken?.isEmpty == false) && pagesFetched < 40

        if !decodedItems.isEmpty {
            await cache.set(decodedItems, forKey: cacheKey)
        }
        return decodedItems
    }

    /// Shared document → model step. Firestore's REST shape is normalised first, and the
    /// document id is injected so models keyed on `id` still resolve.
    private static func decodeDocuments<T: Codable>(_ rawDocs: [[String: Any]]) -> [T] {
        var items: [T] = []
        let decoder = JSONDecoder()

        for rawDoc in rawDocs {
            guard let fields = rawDoc["fields"] as? [String: Any] else { continue }
            var normalized = normalizeFirestoreMap(fields)
            if normalized["id"] == nil || normalized["id"] is NSNull,
               let name = rawDoc["name"] as? String,
               let docId = name.split(separator: "/").last {
                normalized["id"] = String(docId)
            }
            guard let normData = try? JSONSerialization.data(withJSONObject: normalized),
                  let item = try? decoder.decode(T.self, from: normData) else { continue }
            items.append(item)
        }

        return items
    }


    public func fetchDocument<T: Codable>(
        collection: String,
        docId: String,
        idToken: String,
        useCache: Bool = true
    ) async throws -> T {
        let cacheKey = "doc_\(collection)_\(docId)"
        if useCache, let cached: T = await cache.get(forKey: cacheKey, as: T.self) {
            return cached
        }

        let encodedDocId = docId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? docId
        let urlString = "\(FirebaseConfig.firestoreRestBase)/\(collection)/\(encodedDocId)"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            if let cached: T = await cache.get(forKey: cacheKey, as: T.self) {
                return cached
            }
            throw URLError(.badServerResponse)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let fields = json["fields"] as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }

        let normalized = Self.normalizeFirestoreMap(fields)
        let normData = try JSONSerialization.data(withJSONObject: normalized)
        let item = try JSONDecoder().decode(T.self, from: normData)

        await cache.set(item, forKey: cacheKey)
        return item
    }

    // MARK: - Query Helper

    public func runQuery<T: Codable>(
        collection: String,
        whereField field: String,
        equals stringValue: String,
        idToken: String,
        useCache: Bool = true
    ) async throws -> [T] {
        let cacheKey = "query_\(collection)_\(field)_\(stringValue)"
        if useCache, let cached: [T] = await cache.get(forKey: cacheKey, as: [T].self), !cached.isEmpty {
            return cached
        }

        let urlString = "https://firestore.googleapis.com/v1/projects/\(FirebaseConfig.projectId)/databases/(default)/documents:runQuery"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let queryPayload: [String: Any] = [
            "structuredQuery": [
                "from": [["collectionId": collection]],
                "where": [
                    "fieldFilter": [
                        "field": ["fieldPath": field],
                        "op": "EQUAL",
                        "value": ["stringValue": stringValue]
                    ]
                ]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: queryPayload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            if let cached: [T] = await cache.get(forKey: cacheKey, as: [T].self), !cached.isEmpty {
                return cached
            }
            throw URLError(.badServerResponse)
        }

        guard let results = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw URLError(.cannotParseResponse)
        }

        let documents = results.compactMap { $0["document"] as? [String: Any] }
        let items: [T] = Self.decodeDocuments(documents)

        if !items.isEmpty {
            await cache.set(items, forKey: cacheKey)
        }
        return items
    }

    // MARK: - Specific Domain Queries

    public func fetchQBankSubjects(idToken: String) async throws -> [QBankSubject] {
        let subjects: [QBankSubject] = try await fetchCollection(collection: "medx_qbank_subjects", idToken: idToken)
        return subjects.sorted { $0.subjectId < $1.subjectId }
    }

    public func fetchQBankModule(moduleId: String, idToken: String) async throws -> QBankModuleDetail {
        let cacheKey = "qb_mod_\(moduleId)"
        if let cached: QBankModuleDetail = await cache.get(forKey: cacheKey, as: QBankModuleDetail.self) {
            return cached
        }

        let rawDoc: QBankModuleDetail = try await fetchDocument(collection: "medx_qbank_modules", docId: moduleId, idToken: idToken)
        
        // Check if module is split across parts
        if (rawDoc.questions == nil || rawDoc.questions?.isEmpty == true), (rawDoc.partCount ?? 0) > 0 {
            struct ModulePart: Codable {
                let part: Int?
                let questions: [Question]?
            }
            let parts: [ModulePart] = try await runQuery(
                collection: "medx_qbank_module_parts",
                whereField: "moduleId",
                equals: moduleId,
                idToken: idToken
            )
            let sortedQuestions = parts.sorted { ($0.part ?? 0) < ($1.part ?? 0) }.flatMap { $0.questions ?? [] }
            let fullModule = QBankModuleDetail(
                moduleId: rawDoc.moduleId,
                subjectId: rawDoc.subjectId,
                subject: rawDoc.subject,
                chapterId: rawDoc.chapterId,
                chapter: rawDoc.chapter,
                name: rawDoc.name,
                description: rawDoc.description,
                questionCount: sortedQuestions.count,
                questions: sortedQuestions,
                partCount: rawDoc.partCount
            )
            await cache.set(fullModule, forKey: cacheKey)
            return fullModule
        }

        await cache.set(rawDoc, forKey: cacheKey)
        return rawDoc
    }

    public func fetchTests(idToken: String) async throws -> [BatchTest] {
        let tests: [BatchTest] = try await fetchCollection(collection: "medx_tests", idToken: idToken)
        return tests.sorted {
            if $0.gradable != $1.gradable {
                return $0.gradable && !$1.gradable
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    public func fetchTestQuestions(testId: String, idToken: String) async throws -> [Question] {
        struct TestQuestionsPart: Codable {
            let part: Int?
            let questions: [Question]?
        }

        let parts: [TestQuestionsPart] = try await runQuery(
            collection: "medx_test_questions",
            whereField: "testId",
            equals: testId,
            idToken: idToken
        )
        return parts.sorted { ($0.part ?? 0) < ($1.part ?? 0) }.flatMap { $0.questions ?? [] }
    }

    public func fetchFlashcardSubjects(idToken: String) async throws -> [FlashcardSubject] {
        let subjects: [FlashcardSubject] = try await fetchCollection(collection: "medx_flashcard_subjects", idToken: idToken)
        return subjects.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func fetchBookmarks(uid: String, idToken: String) async throws -> [BookmarkedQuestion] {
        let bookmarks: [BookmarkedQuestion] = try await runQuery(
            collection: "medx_bookmarks",
            whereField: "ownerId",
            equals: uid,
            idToken: idToken,
            useCache: false
        )
        return bookmarks
    }

    public func saveBookmark(_ bookmark: BookmarkedQuestion, idToken: String) async throws {
        let safeDocId = bookmark.docId.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: " ", with: "_")
        let urlString = "\(FirebaseConfig.firestoreRestBase)/medx_bookmarks/\(safeDocId)"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encData = try JSONEncoder().encode(bookmark)
        guard let dict = try JSONSerialization.jsonObject(with: encData) as? [String: Any] else { return }

        let firestoreFields = Self.convertToFirestoreFields(dict)
        let body: [String: Any] = ["fields": firestoreFields]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    public func deleteBookmark(docId: String, idToken: String) async throws {
        let safeDocId = docId.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: " ", with: "_")
        let urlString = "\(FirebaseConfig.firestoreRestBase)/medx_bookmarks/\(safeDocId)"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    public func fetchWatchHistory(uid: String, idToken: String) async throws -> [WatchHistoryEntry] {
        let history: [WatchHistoryEntry] = try await runQuery(
            collection: "medx_watch_history",
            whereField: "ownerId",
            equals: uid,
            idToken: idToken,
            useCache: false
        )
        return history
    }

    public func saveWatchHistoryEntry(_ entry: WatchHistoryEntry, idToken: String) async throws {
        let safeDocId = entry.docId.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: " ", with: "_")
        let urlString = "\(FirebaseConfig.firestoreRestBase)/medx_watch_history/\(safeDocId)"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encData = try JSONEncoder().encode(entry)
        guard let dict = try JSONSerialization.jsonObject(with: encData) as? [String: Any] else { return }

        let firestoreFields = Self.convertToFirestoreFields(dict)
        let body: [String: Any] = ["fields": firestoreFields]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    public func deleteWatchHistoryEntry(docId: String, idToken: String) async throws {
        let safeDocId = docId.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: " ", with: "_")
        let urlString = "\(FirebaseConfig.firestoreRestBase)/medx_watch_history/\(safeDocId)"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    public func fetchVideos(idToken: String) async throws -> [RecordedVideo] {
        let videos: [RecordedVideo] = try await fetchCollection(collection: "medx_videos", idToken: idToken)
        return videos
    }

    public func fetchUserAttempts(uid: String, idToken: String) async throws -> [SittingAttempt] {
        let attempts: [SittingAttempt] = try await runQuery(
            collection: "medx_attempts",
            whereField: "uid",
            equals: uid,
            idToken: idToken,
            useCache: false
        )
        return attempts
    }

    public func saveAttempt(_ attempt: SittingAttempt, idToken: String) async throws {
        let urlString = "\(FirebaseConfig.firestoreRestBase)/medx_attempts"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encData = try JSONEncoder().encode(attempt)
        guard let dict = try JSONSerialization.jsonObject(with: encData) as? [String: Any] else { return }

        let firestoreFields = Self.convertToFirestoreFields(dict)
        let body: [String: Any] = ["fields": firestoreFields]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    public func deleteAttempt(_ attempt: SittingAttempt, idToken: String) async throws {
        guard let id = attempt.id, !id.isEmpty else { return }
        let urlString = "\(FirebaseConfig.firestoreRestBase)/medx_attempts/\(id)"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    public func fetchUserTracker(uid: String, idToken: String) async throws -> UserTrackerDoc? {
        do {
            return try await fetchDocument(collection: "user_tracker", docId: uid, idToken: idToken, useCache: false)
        } catch {
            return nil
        }
    }

    public func updateTrackerCell(
        uid: String,
        subject: String,
        field: TrackerField,
        value: Bool,
        idToken: String
    ) async throws {
        let pathKey = "subjects.\(subject).\(field.rawValue)"
        let encodedPath = pathKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? pathKey
        let urlString = "\(FirebaseConfig.firestoreRestBase)/user_tracker/\(uid)?updateMask.fieldPaths=\(encodedPath)"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let fieldVal: [String: Any] = ["booleanValue": value]
        let subjectMap: [String: Any] = ["mapValue": ["fields": [field.rawValue: fieldVal]]]
        let subjectsRoot: [String: Any] = ["mapValue": ["fields": [subject: subjectMap]]]
        let body: [String: Any] = ["fields": ["subjects": subjectsRoot]]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    // MARK: - Normalization Helpers

    public static func normalizeFirestoreMap(_ fields: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, val) in fields {
            if let valDict = val as? [String: Any] {
                result[key] = normalizeFirestoreValue(valDict)
            } else {
                result[key] = val
            }
        }
        return result
    }

    /// Firestore's REST value wrapper → plain JSON.
    ///
    /// This used to fall through to `""` for anything it did not recognise, including
    /// `nullValue`, `{"arrayValue":{}}` (an empty array) and `{"mapValue":{}}` (an empty
    /// map). A `String` where the model expects an object or array is a `typeMismatch`,
    /// `try?` swallowed it, and the whole document was dropped — which is why the Tests
    /// tab rendered nothing at all. Unknown and null values now become `NSNull`, which
    /// `decodeIfPresent` correctly reads as "absent".
    public static func normalizeFirestoreValue(_ valDict: [String: Any]) -> Any {
        if let str = valDict["stringValue"] as? String {
            return str
        }
        if let intStr = valDict["integerValue"] as? String {
            return Int(intStr) ?? 0
        }
        if let intVal = valDict["integerValue"] as? Int {
            return intVal
        }
        if let doubleVal = valDict["doubleValue"] as? Double {
            return doubleVal
        }
        if let doubleStr = valDict["doubleValue"] as? String {
            return Double(doubleStr) ?? 0.0
        }
        if let boolVal = valDict["booleanValue"] as? Bool {
            return boolVal
        }
        if let arrayObj = valDict["arrayValue"] as? [String: Any] {
            let values = arrayObj["values"] as? [[String: Any]] ?? []
            return values.map { normalizeFirestoreValue($0) }
        }
        if let mapObj = valDict["mapValue"] as? [String: Any] {
            let fields = mapObj["fields"] as? [String: Any] ?? [:]
            return normalizeFirestoreMap(fields)
        }
        if let ts = valDict["timestampValue"] as? String {
            return ts
        }
        if let bytes = valDict["bytesValue"] as? String {
            return bytes
        }
        if let reference = valDict["referenceValue"] as? String {
            return reference
        }
        return NSNull()
    }


    public static func convertToFirestoreValue(_ val: Any) -> [String: Any]? {
        if let str = val as? String {
            return ["stringValue": str]
        } else if let int = val as? Int {
            return ["integerValue": String(int)]
        } else if let dbl = val as? Double {
            return ["doubleValue": dbl]
        } else if let bool = val as? Bool {
            return ["booleanValue": bool]
        } else if let subDict = val as? [String: Any] {
            return ["mapValue": ["fields": convertToFirestoreFields(subDict)]]
        } else if let arr = val as? [Any] {
            let values = arr.compactMap { convertToFirestoreValue($0) }
            return ["arrayValue": ["values": values]]
        }
        return nil
    }

    public static func convertToFirestoreFields(_ dict: [String: Any]) -> [String: Any] {
        var fields: [String: Any] = [:]
        for (key, val) in dict {
            if let converted = convertToFirestoreValue(val) {
                fields[key] = converted
            }
        }
        return fields
    }
}

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
        if useCache, let cached: [T] = await cache.get(forKey: cacheKey, as: [T].self) {
            return cached
        }

        let urlString = "\(FirebaseConfig.firestoreRestBase)/\(collection)?pageSize=1000"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            if let cached: [T] = await cache.get(forKey: cacheKey, as: [T].self) {
                return cached
            }
            throw URLError(.badServerResponse)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }

        let rawDocs = json["documents"] as? [[String: Any]] ?? []
        var decodedItems: [T] = []

        for rawDoc in rawDocs {
            if let fields = rawDoc["fields"] as? [String: Any] {
                let normalized = Self.normalizeFirestoreMap(fields)
                if let normData = try? JSONSerialization.data(withJSONObject: normalized),
                   let item = try? JSONDecoder().decode(T.self, from: normData) {
                    decodedItems.append(item)
                }
            }
        }

        await cache.set(decodedItems, forKey: cacheKey)
        return decodedItems
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
        if useCache, let cached: [T] = await cache.get(forKey: cacheKey, as: [T].self) {
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
            if let cached: [T] = await cache.get(forKey: cacheKey, as: [T].self) {
                return cached
            }
            throw URLError(.badServerResponse)
        }

        guard let results = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw URLError(.cannotParseResponse)
        }

        var items: [T] = []
        for res in results {
            if let doc = res["document"] as? [String: Any],
               let fields = doc["fields"] as? [String: Any] {
                var normalized = Self.normalizeFirestoreMap(fields)
                if let name = doc["name"] as? String, let docId = name.split(separator: "/").last {
                    normalized["id"] = String(docId)
                }
                if let normData = try? JSONSerialization.data(withJSONObject: normalized),
                   let item = try? JSONDecoder().decode(T.self, from: normData) {
                    items.append(item)
                }
            }
        }

        await cache.set(items, forKey: cacheKey)
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
        if let boolVal = valDict["booleanValue"] as? Bool {
            return boolVal
        }
        if let arrayObj = valDict["arrayValue"] as? [String: Any],
           let values = arrayObj["values"] as? [[String: Any]] {
            return values.map { normalizeFirestoreValue($0) }
        }
        if let mapObj = valDict["mapValue"] as? [String: Any],
           let fields = mapObj["fields"] as? [String: Any] {
            return normalizeFirestoreMap(fields)
        }
        if let ts = valDict["timestampValue"] as? String {
            return ts
        }
        return ""
    }

    public static func convertToFirestoreFields(_ dict: [String: Any]) -> [String: Any] {
        var fields: [String: Any] = [:]
        for (key, val) in dict {
            if let str = val as? String {
                fields[key] = ["stringValue": str]
            } else if let int = val as? Int {
                fields[key] = ["integerValue": String(int)]
            } else if let bool = val as? Bool {
                fields[key] = ["booleanValue": bool]
            } else if let arr = val as? [[String: Any]] {
                fields[key] = [
                    "arrayValue": [
                        "values": arr.map { ["mapValue": ["fields": convertToFirestoreFields($0)]] }
                    ]
                ]
            } else if let subDict = val as? [String: Any] {
                fields[key] = ["mapValue": ["fields": convertToFirestoreFields(subDict)]]
            }
        }
        return fields
    }
}

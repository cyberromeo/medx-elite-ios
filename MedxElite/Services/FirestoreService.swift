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

    // MARK: - The second bank, and the series
    //
    // Both are single documents under `medx_meta`, seeded by the PWA's
    // `scripts/seed-marrow.mjs`. One read each, which is the whole reason they are shaped
    // that way: the Marrow tree is 20 subjects / 960 modules / 14,577 questions and the
    // series is 376 papers, and neither screen should pay a collection scan to draw a list.

    public func fetchMarrowBankIndex(idToken: String) async throws -> MedxBankIndex {
        try await fetchDocument(collection: "medx_meta", docId: "qbank_fmge", idToken: idToken)
    }

    /// Both banks as one subject list, each entry tagged with where it came from.
    ///
    /// Every consumer — the QBank tabs, a subject page, the custom-module builder — wants the
    /// same tree and differs only in how it filters. A bank that has not been seeded must
    /// leave the other one working, so a Marrow failure is swallowed rather than thrown: the
    /// screen shows ARISE and its segmented control says Marrow is unavailable.
    public func fetchQBankBanks(idToken: String) async throws -> [MedxBankSubject] {
        async let ariseTask = fetchQBankSubjects(idToken: idToken)
        async let marrowTask = fetchMarrowBankIndex(idToken: idToken)

        let arise = try await ariseTask
        let marrow = try? await marrowTask

        return arise.map { MedxBankSubject(arise: $0) } + (marrow?.subjects ?? [])
    }

    public func fetchSeriesIndex(idToken: String) async throws -> MedxSeriesIndex {
        try await fetchDocument(collection: "medx_meta", docId: "series_fmge", idToken: idToken)
    }

    // MARK: - Ordered, paged queries

    /// A page of a collection ordered by one field, with an optional cursor.
    ///
    /// `runQuery` above can only ask a single equality filter, which is all the duel and the
    /// bookmark reads need. The VOD bucket is ~2,900 documents that have to come back newest
    /// first, 48 at a time, so it needs `orderBy` + `limit` + a cursor — and ordering by
    /// `uploadedAt` also filters the collection's `_meta` bookkeeping document out for free,
    /// because Firestore omits documents that lack the ordered field.
    ///
    /// Never cached: a page is a window onto a growing collection, and a cached second page
    /// is a page of the wrong documents.
    public func runOrderedQuery(
        collection: String,
        orderByField: String,
        descending: Bool = true,
        limit: Int,
        startAfterTimestamp: String? = nil,
        idToken: String
    ) async throws -> [[String: Any]] {
        let urlString = "https://firestore.googleapis.com/v1/projects/\(FirebaseConfig.projectId)/databases/(default)/documents:runQuery"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var structured: [String: Any] = [
            "from": [["collectionId": collection]],
            "orderBy": [[
                "field": ["fieldPath": orderByField],
                "direction": descending ? "DESCENDING" : "ASCENDING"
            ]],
            "limit": limit
        ]
        if let startAfterTimestamp {
            // `before: false` is what turns `startAt` into "start *after* this value", which
            // is the difference between paging and re-serving the last row of every page.
            structured["startAt"] = [
                "values": [["timestampValue": startAfterTimestamp]],
                "before": false
            ]
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: ["structuredQuery": structured])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard let results = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw URLError(.cannotParseResponse)
        }
        return results.compactMap { $0["document"] as? [String: Any] }
    }

    // MARK: - The VOD bucket

    /// One page of the feed, newest upload first.
    public func fetchVodPage(pageSize: Int = 48, cursor: String? = nil, idToken: String) async throws -> MedxVodPage {
        let documents = try await runOrderedQuery(
            collection: "medx_vod",
            orderByField: "uploadedAt",
            descending: true,
            limit: pageSize,
            startAfterTimestamp: cursor,
            idToken: idToken
        )

        let items: [MedxVodItem] = documents.compactMap { doc in
            guard let raw = doc["fields"] as? [String: Any] else { return nil }
            let fallbackId = (doc["name"] as? String)?.split(separator: "/").last.map(String.init) ?? ""
            return MedxVodItem(fields: Self.normalizeFirestoreMap(raw), fallbackId: fallbackId)
        }

        return MedxVodPage(
            items: items,
            cursor: items.last?.uploadedAtRaw,
            done: documents.count < pageSize
        )
    }

    /// The watermark. Deliberately one document read, which is what makes the background
    /// new-drop check cheap enough to run on every wake.
    public func fetchVodMeta(idToken: String) async throws -> MedxVodMeta? {
        let urlString = "\(FirebaseConfig.firestoreRestBase)/medx_vod/_meta"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        // A bucket that has never been synced has no `_meta`, which is not an error.
        if http.statusCode == 404 { return nil }
        guard (200...299).contains(http.statusCode) else { throw URLError(.badServerResponse) }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawFields = json["fields"] as? [String: Any] else {
            return nil
        }
        let fields = Self.normalizeFirestoreMap(rawFields)
        let lastRaw = fields["lastUploadedAt"] as? String
        return MedxVodMeta(
            count: (fields["count"] as? Int) ?? 0,
            lastUploadedAt: lastRaw.flatMap { MedxVodItem.parseTimestamp($0) },
            lastUploadedAtRaw: lastRaw,
            updatedAt: (fields["updatedAt"] as? String).flatMap { MedxVodItem.parseTimestamp($0) }
        )
    }

    // MARK: - Custom modules
    //
    // The collection is read *whole* rather than filtered by author: there are two people using
    // this app and one bank behind it, so a paper either of them builds is one the other can
    // run, edit and delete. `uid` on the document records who created it, nothing more.

    public func fetchCustomModules(idToken: String) async throws -> [MedxCustomModule] {
        // Never cached. A stale list here is the one thing that would resurrect a paper the
        // other one deleted, and `MedxCustomModuleRules.reconcile` needs a read it can trust.
        try await fetchCollection(collection: "medx_custom_modules", idToken: idToken, useCache: false)
    }

    public func saveCustomModule(_ module: MedxCustomModule, idToken: String) async throws {
        let urlString = "\(FirebaseConfig.firestoreRestBase)/medx_custom_modules/\(module.id)"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoded = try JSONEncoder().encode(module)
        guard var dict = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else { return }
        // `synced` is this device's bookkeeping and has no business in the shared document.
        dict.removeValue(forKey: "synced")

        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["fields": Self.convertToFirestoreFields(dict)]
        )
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    /// The document id is the whole address, so this works on the other one's paper exactly as
    /// it works on your own — which is the sharing, and is also the one write in this app that
    /// touches a document another account created.
    public func deleteCustomModule(id: String, idToken: String) async throws {
        let urlString = "\(FirebaseConfig.firestoreRestBase)/medx_custom_modules/\(id)"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    /// A single equality filter, returning the raw documents.
    ///
    /// `runQuery` above decodes straight into a `Codable` model and caches, which is right for
    /// bookmarks and attempts. The duel documents are hand-decoded — `askedAt` is epoch millis and
    /// the log is nested maps — and must never be cached, so this stops one step earlier.
    public func runRawQuery(
        collection: String,
        whereField field: String,
        equals stringValue: String,
        idToken: String
    ) async throws -> [[String: Any]] {
        let urlString = "https://firestore.googleapis.com/v1/projects/\(FirebaseConfig.projectId)/databases/(default)/documents:runQuery"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
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
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard let results = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw URLError(.cannotParseResponse)
        }
        return results.compactMap { $0["document"] as? [String: Any] }
    }

    // MARK: - Generic document writes
    //
    // The duel needs shapes the domain helpers above do not cover: several documents committed
    // together, a single field patched without touching its siblings, an `arrayUnion`, and a read
    // of three known documents in one round trip. All four are plain Firestore REST; they live
    // here so the transport stays about the game rather than about HTTP.

    /// Full-document write. `merge` sends an `updateMask` covering exactly the keys given, which
    /// is what stops a partial write blanking the fields it did not mention.
    public func writeDocument(
        collection: String,
        docId: String,
        fields: [String: Any],
        merge: Bool,
        idToken: String
    ) async throws {
        var urlString = "\(FirebaseConfig.firestoreRestBase)/\(collection)/\(docId)"
        if merge {
            let mask = fields.keys
                .compactMap { $0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) }
                .map { "updateMask.fieldPaths=\($0)" }
                .joined(separator: "&")
            if !mask.isEmpty { urlString += "?\(mask)" }
        }
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["fields": Self.convertToFirestoreFields(fields)]
        )

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    /// One write in a `documents:commit` batch.
    ///
    /// `@unchecked` because `fields` is the same `[String: Any]` Firestore's REST shape is built
    /// from everywhere else in this file, and every value in it is a `String`, number, `Bool`,
    /// array or nested dictionary of those. It crosses an actor boundary only as an immutable
    /// value, and a checked `Sendable` here would mean a parallel typed representation of the whole
    /// document shape for no behavioural gain. Without the annotation this is a warning under
    /// Swift 5 and an error under Swift 6.
    public struct MedxWrite: @unchecked Sendable {
        let collection: String
        let docId: String
        let fields: [String: Any]
        /// Field paths to append to, `arrayUnion` style. The values come from `fields[path]`.
        let appendPaths: [String]
        let merge: Bool

        public init(
            collection: String,
            docId: String,
            fields: [String: Any],
            appendPaths: [String] = [],
            merge: Bool = false
        ) {
            self.collection = collection
            self.docId = docId
            self.fields = fields
            self.appendPaths = appendPaths
            self.merge = merge
        }
    }

    /// Several documents in one atomic commit.
    ///
    /// The deal needs this: the deck and the lobby have to become visible together, or the guest
    /// could see a joinable game whose questions have not landed yet.
    ///
    /// `appendPaths` becomes an `appendMissingElements` transform — Firestore's `arrayUnion` —
    /// which de-duplicates by deep equality. That is what makes a re-delivered round advance a
    /// no-op instead of a duplicate log entry.
    public func commit(writes: [MedxWrite], idToken: String) async throws {
        guard !writes.isEmpty else { return }
        let urlString = "https://firestore.googleapis.com/v1/projects/\(FirebaseConfig.projectId)/databases/(default)/documents:commit"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }

        let prefix = "projects/\(FirebaseConfig.projectId)/databases/(default)/documents"
        var payload: [[String: Any]] = []

        for write in writes {
            var plain = write.fields
            var transforms: [[String: Any]] = []
            for path in write.appendPaths {
                guard let value = plain.removeValue(forKey: path),
                      let converted = Self.convertToFirestoreValue(value),
                      let array = converted["arrayValue"] as? [String: Any]
                else { continue }
                transforms.append([
                    "fieldPath": path,
                    "appendMissingElements": array
                ])
            }

            var entry: [String: Any] = [
                "update": [
                    "name": "\(prefix)/\(write.collection)/\(write.docId)",
                    "fields": Self.convertToFirestoreFields(plain)
                ]
            ]
            if write.merge || !transforms.isEmpty {
                entry["updateMask"] = ["fieldPaths": Array(plain.keys)]
            }
            if !transforms.isEmpty {
                entry["updateTransforms"] = transforms
            }
            payload.append(entry)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["writes": payload])

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    /// Several *known* documents in one round trip.
    ///
    /// The duel reads a game plus both player rows on every poll tick, and their ids are
    /// deterministic (`gameId__uid`, with both uids hard-coded in `Profile.allProfiles`), so this
    /// is one request instead of a get plus a query. Missing documents come back as `nil`.
    public func batchGet(
        paths: [(collection: String, docId: String)],
        idToken: String
    ) async throws -> [String: [String: Any]] {
        guard !paths.isEmpty else { return [:] }
        let urlString = "https://firestore.googleapis.com/v1/projects/\(FirebaseConfig.projectId)/databases/(default)/documents:batchGet"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }

        let prefix = "projects/\(FirebaseConfig.projectId)/databases/(default)/documents"
        let names = paths.map { "\(prefix)/\($0.collection)/\($0.docId)" }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["documents": names])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard let results = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw URLError(.cannotParseResponse)
        }

        var out: [String: [String: Any]] = [:]
        for result in results {
            guard let found = result["found"] as? [String: Any],
                  let name = found["name"] as? String,
                  let docId = name.split(separator: "/").last,
                  let rawFields = found["fields"] as? [String: Any]
            else { continue }
            out[String(docId)] = Self.normalizeFirestoreMap(rawFields)
        }
        return out
    }

    /// Deletes any document by collection and id.
    public func deleteDocument(collection: String, docId: String, idToken: String) async throws {
        let urlString = "\(FirebaseConfig.firestoreRestBase)/\(collection)/\(docId)"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
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

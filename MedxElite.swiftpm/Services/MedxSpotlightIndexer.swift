import Foundation
import CoreSpotlight
import UniformTypeIdentifiers

/// Puts bookmarks and modules into the system's own search index, so "Anatomy PYQ" typed
/// on the home screen finds the module and opens it here.
///
/// Everything indexed is content the student already has access to; nothing is uploaded and
/// the whole index can be deleted from Settings.
@MainActor
public final class MedxSpotlightIndexer: ObservableObject {
    public static let shared = MedxSpotlightIndexer()

    public static let bookmarkDomain = "quest.srihari.medxelite.bookmarks"
    public static let moduleDomain = "quest.srihari.medxelite.modules"

    private static let enabledKey = "medx.spotlight.enabled"
    private static let countKey = "medx.spotlight.count"
    /// `indexSearchableItems` is happiest with a few hundred at a time.
    private static let batchSize = 200

    @Published public var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            if !isEnabled {
                Task { await deleteAll() }
            }
        }
    }

    @Published public private(set) var indexedCount: Int
    @Published public private(set) var isIndexing = false

    private init() {
        let defaults = UserDefaults.standard
        isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        indexedCount = defaults.integer(forKey: Self.countKey)
    }

    private var index: CSSearchableIndex { CSSearchableIndex.default() }

    // MARK: - Identifiers

    nonisolated static func bookmarkIdentifier(_ docId: String) -> String { "bookmark:" + docId }

    /// Module metadata rides along inside the identifier.
    ///
    /// A Spotlight tap hands back only the identifier, and the module list may not have been
    /// fetched yet when the app is cold-launched from a search result — so the four things
    /// needed to open the mode picker are packed in rather than looked up.
    nonisolated static func moduleIdentifier(
        id: String,
        questionCount: Int,
        subject: String,
        name: String
    ) -> String {
        let safeSubject = subject.replacingOccurrences(of: "\u{1F}", with: " ")
        let safeName = name.replacingOccurrences(of: "\u{1F}", with: " ")
        return ["module", id, String(questionCount), safeSubject, safeName].joined(separator: "\u{1F}")
    }

    nonisolated static func modulePick(from identifier: String) -> MedxModulePick? {
        let parts = identifier.components(separatedBy: "\u{1F}")
        guard parts.count >= 5, parts[0] == "module" else { return nil }
        return MedxModulePick(
            id: parts[1],
            name: parts[4...].joined(separator: " "),
            subject: parts[3],
            questionCount: Int(parts[2]) ?? 0
        )
    }

    /// Where a Spotlight result should land.
    nonisolated public static func route(for userActivity: NSUserActivity) -> MedxRoute? {
        guard userActivity.activityType == CSSearchableItemActionType,
              let identifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String
        else { return nil }

        if identifier.hasPrefix("bookmark:") { return .bookmarks }
        if let pick = modulePick(from: identifier) { return .module(pick) }
        return nil
    }

    // MARK: - Indexing

    public func indexBookmarks(_ bookmarks: [BookmarkedQuestion]) async {
        guard isEnabled, !bookmarks.isEmpty else { return }

        let items = bookmarks.map { bookmark -> CSSearchableItem in
            let attributes = CSSearchableItemAttributeSet(contentType: UTType.text)
            attributes.title = String(bookmark.previewText.prefix(90))
            attributes.contentDescription = [bookmark.subject, bookmark.sourceName]
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
            attributes.keywords = ["MedX", "bookmark", bookmark.subject, "MCQ"].filter { !$0.isEmpty }
            attributes.contentCreationDate = bookmark.bookmarkedAt

            return CSSearchableItem(
                uniqueIdentifier: Self.bookmarkIdentifier(bookmark.docId),
                domainIdentifier: Self.bookmarkDomain,
                attributeSet: attributes
            )
        }

        await submit(items, label: "bookmarks")
    }

    public func indexModules(_ subjects: [QBankSubject]) async {
        guard isEnabled, !subjects.isEmpty else { return }

        var items: [CSSearchableItem] = []
        for subject in subjects {
            for chapter in subject.chapters ?? [] {
                for module in chapter.modules ?? [] {
                    let attributes = CSSearchableItemAttributeSet(contentType: UTType.text)
                    attributes.title = module.name
                    attributes.contentDescription = "\(subject.name) · \(chapter.name) · "
                        + "\(module.questionCount) questions"
                    attributes.keywords = [
                        "MedX", "QBank", subject.name, chapter.name, "MCQ", "module"
                    ].filter { !$0.isEmpty }
                    // Bigger modules are the more likely target of a vague search.
                    attributes.rankingHint = NSNumber(value: min(module.questionCount, 100))

                    items.append(
                        CSSearchableItem(
                            uniqueIdentifier: Self.moduleIdentifier(
                                id: module.id,
                                questionCount: module.questionCount,
                                subject: subject.name,
                                name: module.name
                            ),
                            domainIdentifier: Self.moduleDomain,
                            attributeSet: attributes
                        )
                    )
                }
            }
        }

        await submit(items, label: "modules")
    }

    private func submit(_ items: [CSSearchableItem], label: String) async {
        guard !items.isEmpty else { return }
        isIndexing = true
        defer { isIndexing = false }

        var written = 0
        for start in stride(from: 0, to: items.count, by: Self.batchSize) {
            let batch = Array(items[start..<min(start + Self.batchSize, items.count)])
            do {
                try await index.indexSearchableItems(batch)
                written += batch.count
            } catch {
                // Spotlight refusing a batch is not worth interrupting anything over.
                print("[Spotlight] \(label) batch failed: \(error)")
                break
            }
        }

        guard written > 0 else { return }
        indexedCount = max(indexedCount, written)
        UserDefaults.standard.set(indexedCount, forKey: Self.countKey)
    }

    public func deleteAll() async {
        do {
            try await index.deleteSearchableItems(
                withDomainIdentifiers: [Self.bookmarkDomain, Self.moduleDomain]
            )
        } catch {
            print("[Spotlight] delete failed: \(error)")
        }
        indexedCount = 0
        UserDefaults.standard.set(0, forKey: Self.countKey)
    }
}

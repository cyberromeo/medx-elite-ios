import SwiftUI

// MARK: - Bookmarks

/// Every question bookmarked in a sitting or a review, newest first, with a subject filter in the
/// toolbar menu. A row opens the question drawn with the runner's own rows, key revealed.
struct BookmarkedQuestionsView: View {
    let uid: String?
    @ObservedObject private var activityStore = ActivityStore.shared
    @State private var searchText = ""
    @State private var selectedSubject: String?
    @State private var showClearAllConfirm = false

    init(uid: String?) {
        self.uid = uid
    }

    private var allBookmarks: [BookmarkedQuestion] {
        activityStore.bookmarks(for: uid)
    }

    private var availableSubjects: [String] {
        Set(allBookmarks.map(\.subject).filter { !$0.isEmpty }).sorted()
    }

    private var filteredBookmarks: [BookmarkedQuestion] {
        allBookmarks.filter { bookmark in
            let matchesSubject = selectedSubject == nil || bookmark.subject == selectedSubject
            let matchesSearch = searchText.isEmpty
                || bookmark.previewText.localizedCaseInsensitiveContains(searchText)
                || bookmark.sourceName.localizedCaseInsensitiveContains(searchText)
                || bookmark.subject.localizedCaseInsensitiveContains(searchText)
            return matchesSubject && matchesSearch
        }
    }

    private var subtitle: String {
        if let selectedSubject { return selectedSubject }
        return allBookmarks.count == 1 ? "1 question" : "\(MedxFormat.count(allBookmarks.count)) questions"
    }

    var body: some View {
        Group {
            if allBookmarks.isEmpty {
                MedxEmptyState(
                    "No bookmarks yet",
                    symbol: MedxFeature.bookmarks.symbol,
                    message: "Bookmark a question during a sitting or its review and it is kept here."
                )
            } else {
                List {
                    Section {
                        ForEach(filteredBookmarks) { bookmark in
                            NavigationLink {
                                BookmarkedQuestionDetailView(bookmark: bookmark, uid: uid)
                            } label: {
                                row(bookmark)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    HapticManager.medium()
                                    activityStore.removeBookmark(bookmark, uid: uid)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    } footer: {
                        Text("\(filteredBookmarks.count) of \(allBookmarks.count) bookmarks. Swipe left to remove one.")
                    }
                }
                .listStyle(.insetGrouped)
                .searchable(text: $searchText, prompt: "Search bookmarks")
            }
        }
        .navigationTitle(MedxFeature.bookmarks.title)
        .navigationSubtitle(subtitle)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if !allBookmarks.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if availableSubjects.count > 1 {
                            Picker("Subject", selection: $selectedSubject) {
                                Text("All subjects").tag(String?.none)
                                ForEach(availableSubjects, id: \.self) { subject in
                                    Text(subject).tag(String?.some(subject))
                                }
                            }
                            Divider()
                        }
                        Button(role: .destructive) {
                            showClearAllConfirm = true
                        } label: {
                            Label("Clear all bookmarks", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Filter and manage bookmarks")
                }
            }
        }
        .confirmationDialog(
            "Clear all bookmarks?",
            isPresented: $showClearAllConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear \(allBookmarks.count) bookmarks", role: .destructive) {
                HapticManager.medium()
                activityStore.clearAllBookmarks(uid: uid)
            }
            Button("Keep them", role: .cancel) {}
        } message: {
            Text("They go from this device and from your account.")
        }
    }

    private func row(_ bookmark: BookmarkedQuestion) -> some View {
        VStack(alignment: .leading, spacing: MedxSpace.xs) {
            Text(bookmark.previewText)
                .lineLimit(3)

            Text([bookmark.subject, bookmark.sourceName, bookmark.formattedDate]
                .filter { !$0.isEmpty }
                .joined(separator: " · "))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - One bookmark

private struct BookmarkedQuestionDetailView: View {
    let bookmark: BookmarkedQuestion
    let uid: String?
    @ObservedObject private var activityStore = ActivityStore.shared
    @Environment(\.dismiss) private var dismiss

    private var question: Question { bookmark.question }

    private var reference: String {
        question.reference?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: MedxSpace.m) {
                    Text([bookmark.sourceName, bookmark.formattedDate].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    HTMLRichTextView(html: question.displayText, fontSize: 16, weight: .semibold)

                    if let images = question.images, !images.isEmpty {
                        ForEach(images, id: \.self) { raw in
                            RunnerFigure(raw: raw)
                        }
                    }

                    VStack(spacing: MedxSpace.s) {
                        ForEach(Array(question.options.enumerated()), id: \.offset) { pair in
                            QuestionOptionButton(
                                option: pair.element,
                                index: pair.offset,
                                isChosen: false,
                                isCorrect: question.isCorrect(optionId: pair.element.id),
                                isRevealed: question.hasAnswerKey,
                                isLocked: true
                            ) {}
                        }
                    }

                    if (question.explanation?.isEmpty == false) || !reference.isEmpty {
                        VStack(alignment: .leading, spacing: MedxSpace.s) {
                            Label("Explanation", systemImage: "lightbulb.fill")
                                .font(.subheadline.weight(.semibold))

                            if let explanation = question.explanation, !explanation.isEmpty {
                                HTMLRichTextView(html: explanation, fontSize: 15, weight: .regular, textColor: .secondary)
                            }

                            if !reference.isEmpty {
                                Label(reference, systemImage: "book.closed")
                                    .font(.footnote)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.top, MedxSpace.xs)
                    }
                }
                .padding(.vertical, MedxSpace.xs)
            }

            Section {
                Button(role: .destructive) {
                    HapticManager.medium()
                    activityStore.removeBookmark(bookmark, uid: uid)
                    dismiss()
                } label: {
                    Label("Remove bookmark", systemImage: "bookmark.slash")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(bookmark.subject.isEmpty ? "Question" : bookmark.subject)
        .navigationBarTitleDisplayMode(.inline)
    }
}

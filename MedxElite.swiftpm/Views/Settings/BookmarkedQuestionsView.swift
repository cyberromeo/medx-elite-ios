import SwiftUI

// MARK: - Bookmarked Questions View

struct BookmarkedQuestionsView: View {
    let uid: String?
    @ObservedObject private var activityStore = ActivityStore.shared
    @State private var searchText = ""
    @State private var selectedSubject: String = "All"
    @State private var showClearAllConfirm = false
    @State private var practicePayload: RunnerPayload?

    init(uid: String?) {
        self.uid = uid
    }

    private var allBookmarks: [BookmarkedQuestion] {
        activityStore.bookmarks(for: uid)
    }

    private var availableSubjects: [String] {
        let list = Set(allBookmarks.map { $0.subject }.filter { !$0.isEmpty })
        return ["All"] + list.sorted()
    }

    private var filteredBookmarks: [BookmarkedQuestion] {
        allBookmarks.filter { bookmark in
            let matchesSubject = selectedSubject == "All" || bookmark.subject == selectedSubject
            let matchesSearch = searchText.isEmpty ||
                bookmark.previewText.localizedCaseInsensitiveContains(searchText) ||
                bookmark.sourceName.localizedCaseInsensitiveContains(searchText) ||
                bookmark.subject.localizedCaseInsensitiveContains(searchText)
            return matchesSubject && matchesSearch
        }
    }

    var body: some View {
        Group {
            if allBookmarks.isEmpty {
                ContentUnavailableView(
                    "No Bookmarks",
                    systemImage: "bookmark",
                    description: Text("Bookmark MCQs during a sitting session or review to revise them here.")
                )
            } else {
                List {
                    // Subject Filter Chips
                    if availableSubjects.count > 2 {
                        Section {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(availableSubjects, id: \.self) { subj in
                                        Button {
                                            HapticManager.selection()
                                            selectedSubject = subj
                                        } label: {
                                            Text(subj)
                                                .font(.caption.weight(.semibold))
                                                .foregroundColor(selectedSubject == subj ? .white : .primary)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(
                                                    selectedSubject == subj ? MedxTheme.primaryPurple : Color(uiColor: .tertiarySystemFill),
                                                    in: Capsule()
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }

                    Section {
                        ForEach(filteredBookmarks) { bookmark in
                            NavigationLink {
                                BookmarkedQuestionDetailView(bookmark: bookmark, uid: uid)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(bookmark.previewText)
                                        .font(.body)
                                        .lineLimit(3)

                                    HStack(spacing: 6) {
                                        if !bookmark.subject.isEmpty {
                                            Text(bookmark.subject)
                                                .font(.caption2.weight(.bold).monospacedDigit())
                                                .foregroundColor(MedxTheme.primaryPurple)
                                                .padding(.horizontal, 7)
                                                .padding(.vertical, 2)
                                                .background(MedxTheme.primaryPurple.opacity(0.12), in: Capsule())
                                        }

                                        Text(bookmark.sourceName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)

                                        Spacer()

                                        Text(bookmark.formattedDate)
                                            .font(.caption)
                                            .foregroundStyle(Color(uiColor: .tertiaryLabel))
                                    }
                                }
                                .padding(.vertical, 4)
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
                        Text("\(filteredBookmarks.count) of \(allBookmarks.count) bookmarked questions")
                            .font(.caption)
                    }
                }
                .searchable(text: $searchText, prompt: "Search bookmarks…")
            }
        }
        .navigationTitle("Bookmarks")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !allBookmarks.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            showClearAllConfirm = true
                        } label: {
                            Label("Clear All Bookmarks", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .frame(width: 44, height: 44)
                    }
                }
            }
        }
        .confirmationDialog(
            "Clear All Bookmarks?",
            isPresented: $showClearAllConfirm
        ) {
            Button("Clear All", role: .destructive) {
                HapticManager.medium()
                activityStore.clearAllBookmarks(uid: uid)
            }
        } message: {
            Text("This will remove all bookmarked questions locally and from your cloud account.")
        }
    }
}

// MARK: - Bookmarked Question Detail View

private struct BookmarkedQuestionDetailView: View {
    let bookmark: BookmarkedQuestion
    let uid: String?
    @ObservedObject private var activityStore = ActivityStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Header meta badge
                HStack {
                    if !bookmark.subject.isEmpty {
                        Text(bookmark.subject)
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundColor(MedxTheme.primaryPurple)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(MedxTheme.primaryPurple.opacity(0.12), in: Capsule())
                    }

                    Text(bookmark.sourceName)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Text(bookmark.formattedDate)
                        .font(.caption)
                        .foregroundColor(Color(uiColor: .tertiaryLabel))
                }

                // Question HTML display
                HTMLRichTextView(html: bookmark.question.displayText, fontSize: 17, weight: .semibold)

                // Images if any
                if let imgs = bookmark.question.images, !imgs.isEmpty {
                    ForEach(imgs, id: \.self) { imgUrl in
                        CachedAsyncImage(url: URL(string: imgUrl))
                            .frame(maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }

                // Options with Answer Key
                VStack(spacing: 10) {
                    ForEach(Array(bookmark.question.options.enumerated()), id: \.offset) { pair in
                        let option = pair.element
                        let isCorrect = bookmark.question.isCorrect(optionId: option.id)

                        HStack(alignment: .medxFirstLine, spacing: 12) {
                            Text(MedxOptionLetter.of(option, at: pair.offset))
                                .font(.footnote.weight(.bold).monospacedDigit())
                                .foregroundColor(isCorrect ? .white : .primary)
                                .frame(width: 28, height: 28)
                                .background(isCorrect ? MedxTheme.successGreen : Color.primary.opacity(0.08))
                                .clipShape(Circle())

                            HTMLRichTextView(html: option.text, fontSize: 14, weight: .regular)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .medxFirstLineGuide(fontSize: 14)
                                .layoutPriority(1)

                            Spacer(minLength: 0)

                            if isCorrect {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.headline)
                                    .foregroundColor(MedxTheme.successGreen)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .center)
                        .background(isCorrect ? MedxTheme.successGreen.opacity(0.12) : Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(isCorrect ? MedxTheme.successGreen.opacity(0.4) : Color.clear, lineWidth: 1)
                        )
                    }
                }

                // Explanation
                if let explanation = bookmark.question.explanation, !explanation.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Explanation", systemImage: "lightbulb.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(MedxTheme.warningOrange)
                        HTMLRichTextView(html: explanation, fontSize: 15, weight: .regular, textColor: .secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .medxCard()
                }

                // Remove Bookmark Button
                Button(role: .destructive) {
                    HapticManager.medium()
                    activityStore.removeBookmark(bookmark, uid: uid)
                    dismiss()
                } label: {
                    Label("Remove Bookmark", systemImage: "bookmark.slash")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .medxBorderedButton()
                .tint(MedxTheme.destructiveRed)
                .padding(.top, 10)
            }
            .padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Question Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}

import SwiftUI

public struct FlashcardsSubjectListView: View {
    @ObservedObject var authService = AuthService.shared
    @State private var subjects: [FlashcardSubject] = []
    @State private var searchText = ""
    @State private var isLoading = true

    public init() {}

    private var filteredSubjects: [FlashcardSubject] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return subjects
        }
        return subjects.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    public var body: some View {
        List {
            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView("Loading Flashcards...")
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    let totalCards = subjects.reduce(0) { $0 + $1.cardCount }
                    Text("\(totalCards.formatted()) cards · \(subjects.count) subjects")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Section {
                    ForEach(filteredSubjects) { subject in
                        NavigationLink {
                            FlashcardStudyView(subject: subject)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "sparkles.rectangle.stack.fill")
                                    .font(.title3)
                                    .foregroundColor(.purple)
                                    .frame(width: 32)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(subject.name)
                                        .font(.headline)

                                    Text("\(subject.cardCount) cards")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Text("\(subject.cardCount)")
                                    .font(.caption.bold())
                                    .foregroundColor(.purple)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.purple.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Flashcards")
        .searchable(text: $searchText, prompt: "Search subjects")
        .refreshable {
            await loadFlashcards()
        }
        .task {
            await loadFlashcards()
        }
    }

    private func loadFlashcards() async {
        do {
            let token = try await authService.getValidIdToken()
            self.subjects = try await FirestoreService.shared.fetchFlashcardSubjects(idToken: token)
            self.isLoading = false
        } catch {
            self.isLoading = false
        }
    }
}

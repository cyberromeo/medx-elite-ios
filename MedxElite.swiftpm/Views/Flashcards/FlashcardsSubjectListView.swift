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
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()

                if isLoading {
                    ProgressView("Loading Flashcards...")
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            let totalCards = subjects.reduce(0) { $0 + $1.cardCount }

                            HStack {
                                Text("\(totalCards.formatted()) cards · \(subjects.count) subjects")
                                    .font(MedxFont.rounded(13, weight: .medium))
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 4)

                            // Search Field
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(.secondary)
                                TextField("Search flashcard subjects...", text: $searchText)
                                    .font(MedxFont.rounded(15, weight: .regular))
                                if !searchText.isEmpty {
                                    Button {
                                        searchText = ""
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding(12)
                            .liquidGlassCard(cornerRadius: 14)
                            .padding(.horizontal, 20)

                            // Subject Rows
                            LazyVStack(spacing: 12) {
                                ForEach(filteredSubjects) { subject in
                                    NavigationLink {
                                        FlashcardStudyView(subject: subject)
                                    } label: {
                                        HStack(spacing: 14) {
                                            ZStack {
                                                Circle()
                                                    .fill(MedxTheme.primaryPurple.opacity(0.12))
                                                    .frame(width: 44, height: 44)
                                                Image(systemName: "sparkles.rectangle.stack.fill")
                                                    .font(.headline)
                                                    .foregroundColor(MedxTheme.primaryPurple)
                                            }

                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(subject.name)
                                                    .font(MedxFont.rounded(16, weight: .bold))
                                                    .foregroundColor(.primary)

                                                Text("\(subject.cardCount) cards")
                                                    .font(MedxFont.rounded(13, weight: .regular))
                                                    .foregroundColor(.secondary)
                                            }

                                            Spacer()

                                            Text("\(subject.cardCount)")
                                                .font(MedxFont.monospacedDigits(12, weight: .bold))
                                                .foregroundColor(MedxTheme.primaryPurple)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(MedxTheme.primaryPurple.opacity(0.12))
                                                .clipShape(Capsule())

                                            Image(systemName: "chevron.right")
                                                .font(.subheadline)
                                                .foregroundColor(.secondary.opacity(0.6))
                                        }
                                        .padding(16)
                                        .liquidGlassCard(cornerRadius: 18)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 90)
                        }
                    }
                    .refreshable {
                        await loadFlashcards()
                    }
                }
            }
            .navigationTitle("Flashcards")
            .navigationBarTitleDisplayMode(.large)
            .task {
                await loadFlashcards()
            }
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

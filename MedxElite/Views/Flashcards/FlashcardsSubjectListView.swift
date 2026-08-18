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
        ZStack {
            ambientBackground

            if isLoading {
                ProgressView("Loading Flashcards…")
                    .controlSize(.large)
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        // Summary stat pill
                        let totalCards = subjects.reduce(0) { $0 + $1.cardCount }
                        HStack(spacing: 12) {
                            statPill(icon: "sparkles.rectangle.stack.fill", value: totalCards.formatted(), label: "cards", color: MedxTheme.primaryPurple)
                            statPill(icon: "books.vertical.fill", value: "\(subjects.count)", label: "subjects", color: MedxTheme.primaryPink)
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 6)

                        // Subject List
                        LazyVStack(spacing: 12) {
                            ForEach(filteredSubjects) { subject in
                                NavigationLink {
                                    FlashcardStudyView(subject: subject)
                                } label: {
                                    subjectRow(subject)
                                }
                                .buttonStyle(.plain)
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
        .searchable(text: $searchText, prompt: "Search flashcard subjects…")
        .task {
            await loadFlashcards()
        }
    }

    private func subjectRow(_ subject: FlashcardSubject) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [MedxTheme.primaryPurple.opacity(0.2), MedxTheme.primaryPink.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)

                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(MedxTheme.primaryPurple)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(subject.name)
                    .font(MedxFont.headline(16))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text("\(subject.cardCount) visual flashcards")
                    .font(MedxFont.caption(12))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text("\(subject.cardCount)")
                .font(MedxFont.mono(12, weight: .bold))
                .foregroundColor(MedxTheme.primaryPurple)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(MedxTheme.primaryPurple.opacity(0.12), in: Capsule())

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(uiColor: .tertiaryLabel))
        }
        .padding(16)
        .medxNavigationGlass(cornerRadius: 20, tint: MedxTheme.primaryPurple)
    }

        private func statPill(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(color)
                Text(value)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .allowsTightening(true)
            }
            Text(label.capitalized)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 50)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(color.opacity(0.08), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }

    private var ambientBackground: some View {
        Color(uiColor: .systemGroupedBackground)
            .ignoresSafeArea()
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

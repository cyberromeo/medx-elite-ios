import SwiftUI

public struct VideosBatchListView: View {
    @ObservedObject var authService = AuthService.shared
    @State private var videos: [RecordedVideo] = []
    @State private var isLoading = true

    public init() {}

    private var batchGroups: [VideoBatchGroup] {
        var batchMap: [String: (name: String, totalSeconds: Int, count: Int, subjects: [String: (name: String, totalSeconds: Int, videos: [RecordedVideo])])] = [:]

        for v in videos {
            let bId = v.batchId ?? "default"
            let bName = v.batch ?? "Batch"
            let sId = v.subjectId ?? "sub"
            let sName = v.subject
            let dur = v.durationSeconds ?? 0

            var batchEntry = batchMap[bId] ?? (name: bName, totalSeconds: 0, count: 0, subjects: [:])
            batchEntry.totalSeconds += dur
            batchEntry.count += 1

            var subEntry = batchEntry.subjects[sId] ?? (name: sName, totalSeconds: 0, videos: [])
            subEntry.totalSeconds += dur
            subEntry.videos.append(v)
            batchEntry.subjects[sId] = subEntry

            batchMap[bId] = batchEntry
        }

        return batchMap.map { (bId, bData) in
            let subjectGroups = bData.subjects.map { (sId, sData) in
                VideoSubjectGroup(
                    subjectId: sId,
                    name: sData.name,
                    totalSeconds: sData.totalSeconds,
                    totalClasses: sData.videos.count,
                    videos: sData.videos
                )
            }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

            return VideoBatchGroup(
                batchId: bId,
                name: bData.name,
                totalSeconds: bData.totalSeconds,
                totalClasses: bData.count,
                subjects: subjectGroups
            )
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()

                if isLoading {
                    ProgressView("Loading Videos...")
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            HStack {
                                Text("\(videos.count) recorded classes · ARISE")
                                    .font(MedxFont.rounded(13, weight: .medium))
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 6)

                            ForEach(batchGroups) { batch in
                                VStack(alignment: .leading, spacing: 14) {
                                    Text(batch.name)
                                        .font(MedxFont.rounded(18, weight: .bold))
                                        .padding(.horizontal, 20)

                                    LazyVStack(spacing: 12) {
                                        ForEach(batch.subjects) { subject in
                                            NavigationLink {
                                                VideoSubjectView(subjectGroup: subject)
                                            } label: {
                                                HStack(spacing: 14) {
                                                    ZStack {
                                                        Circle()
                                                            .fill(MedxTheme.primaryBlue.opacity(0.12))
                                                            .frame(width: 44, height: 44)
                                                        Image(systemName: "play.rectangle.fill")
                                                            .font(.headline)
                                                            .foregroundColor(MedxTheme.primaryBlue)
                                                    }

                                                    VStack(alignment: .leading, spacing: 3) {
                                                        Text(subject.name)
                                                            .font(MedxFont.rounded(16, weight: .bold))
                                                            .foregroundColor(.primary)

                                                        Text("\(subject.totalClasses) classes · \(subject.formattedDuration)")
                                                            .font(MedxFont.rounded(13, weight: .regular))
                                                            .foregroundColor(.secondary)
                                                    }

                                                    Spacer()

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
                                }
                            }
                        }
                        .padding(.bottom, 90)
                    }
                    .refreshable {
                        await loadVideos()
                    }
                }
            }
            .navigationTitle("Videos")
            .navigationBarTitleDisplayMode(.large)
            .task {
                await loadVideos()
            }
        }
    }

    private func loadVideos() async {
        do {
            let token = try await authService.getValidIdToken()
            self.videos = try await FirestoreService.shared.fetchVideos(idToken: token)
            self.isLoading = false
        } catch {
            self.isLoading = false
        }
    }
}

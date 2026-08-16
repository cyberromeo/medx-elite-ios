import SwiftUI

public struct VideosBatchListView: View {
    @ObservedObject var authService = AuthService.shared
    @State private var videos: [RecordedVideo] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var expandedBatches: Set<String> = []

    public init() {}

    private var batchGroups: [VideoBatchGroup] {
        var batchMap: [String: (name: String, totalSeconds: Int, count: Int, subjects: [String: (name: String, totalSeconds: Int, videos: [RecordedVideo])])] = [:]

        let filteredVideos = searchText.isEmpty ? videos : videos.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.subject.localizedCaseInsensitiveContains(searchText) ||
            ($0.faculty ?? "").localizedCaseInsensitiveContains(searchText)
        }

        for v in filteredVideos {
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
        ZStack {
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()

            if isLoading {
                // Skeleton loading
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(0..<4, id: \.self) { _ in
                            skeletonCard
                        }
                    }
                    .padding(20)
                }
            } else if videos.isEmpty {
                ContentUnavailableView(
                    "No Videos",
                    systemImage: "play.tv",
                    description: Text("Videos will appear here once loaded.")
                )
            } else {
                ScrollView {
                    VStack(spacing: 24) {
                        // Stats header
                        HStack(spacing: 12) {
                            statPill(
                                icon: "play.rectangle.fill",
                                value: "\(videos.count)",
                                label: "classes",
                                color: MedxTheme.primaryBlue
                            )

                            statPill(
                                icon: "clock.fill",
                                value: totalDurationFormatted,
                                label: "total",
                                color: MedxTheme.primaryPurple
                            )

                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 6)

                        // Batch groups
                        ForEach(batchGroups) { batch in
                            batchSection(batch)
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
        .searchable(text: $searchText, prompt: "Search videos, subjects, faculty…")
        .task {
            await loadVideos()
        }
    }

    // MARK: - Batch Section

    private func batchSection(_ batch: VideoBatchGroup) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Batch header
            HStack {
                Text(batch.name)
                    .font(MedxFont.headline(18))

                Spacer()

                Text("\(batch.totalClasses) classes")
                    .font(MedxFont.caption(12))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)

            LazyVStack(spacing: 10) {
                ForEach(batch.subjects) { subject in
                    NavigationLink {
                        VideoSubjectView(subjectGroup: subject)
                    } label: {
                        subjectRow(subject)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Subject Row

    private func subjectRow(_ subject: VideoSubjectGroup) -> some View {
        HStack(spacing: 14) {
            // Subject icon with gradient tint
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(MedxTheme.primaryBlue.opacity(0.1))
                    .frame(width: 46, height: 46)

                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(MedxTheme.primaryBlue)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(subject.name)
                    .font(MedxFont.headline(16))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text("\(subject.totalClasses) classes")
                        .font(MedxFont.caption(12))
                        .foregroundColor(.secondary)

                    Text("·")
                        .foregroundColor(.quaternaryLabel)

                    Text(subject.formattedDuration)
                        .font(MedxFont.mono(12, weight: .semibold))
                        .foregroundColor(MedxTheme.primaryBlue)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.tertiaryLabel)
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: 16)
    }

    // MARK: - Stat Pill

    private func statPill(icon: String, value: String, label: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(color)

            Text("\(value) \(label)")
                .font(MedxFont.label(12))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.08), in: Capsule())
    }

    // MARK: - Skeleton

    private var skeletonCard: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 14)
                    .frame(maxWidth: 180)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
                    .frame(height: 10)
                    .frame(maxWidth: 120)
            }
            Spacer()
        }
        .padding(16)
        .liquidGlassCard(cornerRadius: 16)
        .redacted(reason: .placeholder)
    }

    // MARK: - Computed

    private var totalDurationFormatted: String {
        let total = videos.compactMap { $0.durationSeconds }.reduce(0, +)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    // MARK: - Data

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

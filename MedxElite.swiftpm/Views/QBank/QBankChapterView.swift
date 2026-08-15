import SwiftUI

public struct QBankChapterView: View {
    public let subject: QBankSubject
    public let attempts: [SittingAttempt]
    public var onStartModule: (QBankModuleSummary, SittingMode) -> Void

    @State private var selectedModuleForStart: QBankModuleSummary?

    public init(
        subject: QBankSubject,
        attempts: [SittingAttempt],
        onStartModule: @escaping (QBankModuleSummary, SittingMode) -> Void
    ) {
        self.subject = subject
        self.attempts = attempts
        self.onStartModule = onStartModule
    }

    private var moduleAttemptsMap: [String: (count: Int, best: Int, total: Int)] {
        var map: [String: (count: Int, best: Int, total: Int)] = [:]
        for a in attempts where a.kind == "qbank" {
            let current = map[a.sourceId] ?? (count: 0, best: 0, total: a.total)
            map[a.sourceId] = (
                count: current.count + 1,
                best: max(current.best, a.score),
                total: a.total
            )
        }
        return map
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header Info
                VStack(spacing: 6) {
                    Text("\(subject.moduleCount) modules · \((subject.questionCount ?? 0).formatted()) questions")
                        .font(MedxFont.rounded(14, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 10)

                // Chapters & Modules
                let chapters = subject.chapters ?? []
                ForEach(chapters) { chapter in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(chapter.name)
                            .font(MedxFont.rounded(16, weight: .bold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 20)

                        VStack(spacing: 10) {
                            ForEach(chapter.modules ?? []) { module in
                                let attemptInfo = moduleAttemptsMap[module.id]

                                Button {
                                    HapticManager.light()
                                    selectedModuleForStart = module
                                } label: {
                                    HStack(spacing: 14) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(module.name)
                                                .font(MedxFont.rounded(15, weight: .bold))
                                                .foregroundColor(.primary)
                                                .multilineTextAlignment(.leading)

                                            if let info = attemptInfo {
                                                Text("\(module.questionCount) questions · best \(info.best)/\(info.total) · \(info.count) sitting\(info.count == 1 ? "" : "s")")
                                                    .font(MedxFont.rounded(12, weight: .medium))
                                                    .foregroundColor(MedxTheme.successGreen)
                                            } else {
                                                Text("\(module.questionCount) questions")
                                                    .font(MedxFont.rounded(12, weight: .medium))
                                                    .foregroundColor(.secondary)
                                            }
                                        }

                                        Spacer()

                                        if attemptInfo != nil {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(MedxTheme.successGreen)
                                                .font(.headline)
                                        } else {
                                            Image(systemName: "play.circle.fill")
                                                .foregroundColor(MedxTheme.primaryBlue.opacity(0.8))
                                                .font(.title3)
                                        }
                                    }
                                    .padding(16)
                                    .liquidGlassCard(cornerRadius: 16)
                                }
                                .buttonStyle(BouncyButtonStyle())
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
            }
            .padding(.bottom, 40)
        }
        .navigationTitle(subject.name)
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $selectedModuleForStart) { mod in
            StartSessionSheet(
                title: mod.name,
                subtitle: subject.name,
                questionCount: mod.questionCount
            ) { mode in
                onStartModule(mod, mode)
            }
        }
    }
}

import SwiftUI

public struct SyllabusTrackerSheet: View {
    public let uid: String
    @Binding public var trackerDoc: UserTrackerDoc?
    @State private var savingCell: String?
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    public init(uid: String, trackerDoc: Binding<UserTrackerDoc?>) {
        self.uid = uid
        self._trackerDoc = trackerDoc
    }

    private var subjectsList: [(name: String, fields: SubjectTrackerFields)] {
        guard let subjects = trackerDoc?.subjects else { return [] }
        return subjects.map { (name: $0.key, fields: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var totals: (done: Int, total: Int) {
        var done = 0
        var total = 0
        for (_, fields) in subjectsList {
            for f in TrackerField.allCases {
                if let val = fields.value(for: f) {
                    total += 1
                    if val { done += 1 }
                }
            }
        }
        return (done: done, total: total)
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Header Summary Card
                        VStack(spacing: 14) {
                            HStack {
                                Text("Syllabus Progress")
                                    .font(MedxFont.headline(16))
                                Spacer()
                                Text("\(totals.done) of \(totals.total) done")
                                    .font(MedxFont.mono(14, weight: .bold))
                                    .foregroundColor(MedxTheme.primaryBlue)
                            }

                            let progress = totals.total > 0 ? Double(totals.done) / Double(totals.total) : 0.0
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.primary.opacity(0.08))
                                        .frame(height: 8)

                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [MedxTheme.primaryBlue, MedxTheme.cyanAccent],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(width: geo.size.width * CGFloat(progress), height: 8)
                                        .animation(.spring(), value: progress)
                                }
                            }
                            .frame(height: 8)

                            Text("\(totals.total - totals.done) items left across \(subjectsList.count) subjects")
                                .font(MedxFont.caption(13))
                                .foregroundColor(.secondary)
                        }
                        .padding(20)
                        .liquidGlassCard(cornerRadius: 20, glowColor: MedxTheme.primaryBlue)
                        .padding(.horizontal, 20)

                        if let err = errorMessage {
                            Text(err)
                                .font(MedxFont.caption(13))
                                .foregroundColor(MedxTheme.destructiveRed)
                                .padding(.horizontal, 20)
                        }

                        // Subject Matrix Cards
                        VStack(spacing: 12) {
                            ForEach(subjectsList, id: \.name) { subject in
                                SubjectTrackerRow(
                                    subjectName: subject.name,
                                    fields: subject.fields,
                                    isSaving: savingCell?.starts(with: subject.name) == true
                                ) { field, currentVal in
                                    toggleCell(subject: subject.name, field: field, currentVal: currentVal)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 30)
                    }
                    .padding(.top, 16)
                }
            }
            .navigationTitle("Syllabus Tracker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(MedxFont.headline(16))
                }
            }
        }
    }

    private func toggleCell(subject: String, field: TrackerField, currentVal: Bool) {
        let cellKey = "\(subject).\(field.rawValue)"
        savingCell = cellKey
        errorMessage = nil
        HapticManager.selection()

        // Optimistic UI update
        if var subs = trackerDoc?.subjects, var sFields = subs[subject] {
            sFields.setValue(!currentVal, for: field)
            subs[subject] = sFields
            trackerDoc = UserTrackerDoc(subjects: subs)
        }

        Task {
            do {
                let token = try await AuthService.shared.getValidIdToken()
                try await FirestoreService.shared.updateTrackerCell(
                    uid: uid,
                    subject: subject,
                    field: field,
                    value: !currentVal,
                    idToken: token
                )
                savingCell = nil
                HapticManager.success()
            } catch {
                errorMessage = "Failed to sync: \(error.localizedDescription)"
                savingCell = nil
                HapticManager.error()
            }
        }
    }
}

private struct SubjectTrackerRow: View {
    let subjectName: String
    let fields: SubjectTrackerFields
    let isSaving: Bool
    let onToggle: (TrackerField, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(subjectName)
                .font(MedxFont.headline(15))
                .foregroundColor(.primary)

            HStack(spacing: 8) {
                ForEach(TrackerField.allCases) { field in
                    let hasValue = fields.value(for: field) != nil
                    let isChecked = fields.value(for: field) == true

                    Button {
                        if hasValue {
                            onToggle(field, isChecked)
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Text(field.label)
                                .font(MedxFont.label(11))
                                .foregroundColor(isChecked ? .white : (hasValue ? .primary : .secondary.opacity(0.4)))

                            Image(systemName: isChecked ? "checkmark" : (hasValue ? "circle" : "minus"))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(isChecked ? .white : (hasValue ? .secondary : .secondary.opacity(0.3)))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(isChecked ? MedxTheme.primaryBlue : (hasValue ? Color.primary.opacity(0.04) : Color.clear))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(!hasValue)
                }
            }
        }
        .padding(16)
        .liquidGlassCard(cornerRadius: 16)
    }
}

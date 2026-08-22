import SwiftUI

/// The 23-subject × 6-stage revision matrix. Written straight to Firestore per cell, with
/// the local value flipped first so the tap feels instant.
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
        return subjects
            .map { (name: $0.key, fields: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var totals: (done: Int, total: Int) {
        var done = 0
        var total = 0
        for (_, fields) in subjectsList {
            for field in TrackerField.allCases {
                guard let value = fields.value(for: field) else { continue }
                total += 1
                if value { done += 1 }
            }
        }
        return (done, total)
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    summaryCard

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(MedxTheme.destructiveRed)
                            .padding(.horizontal, 2)
                    }

                    if subjectsList.isEmpty {
                        ContentUnavailableView(
                            "No Checklist Yet",
                            systemImage: "checklist",
                            description: Text("Your syllabus matrix will appear here once it has been set up on your account.")
                        )
                        .padding(.top, 32)
                    } else {
                        ForEach(subjectsList, id: \.name) { subject in
                            SubjectTrackerRow(
                                subjectName: subject.name,
                                fields: subject.fields,
                                isSaving: savingCell?.hasPrefix(subject.name) == true
                            ) { field, currentValue in
                                toggleCell(subject: subject.name, field: field, currentValue: currentValue)
                            }
                        }
                    }
                }
                .padding(.horizontal, MedxSurface.gutter)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .background(MedxSurface.groupedBackground.ignoresSafeArea())
            .navigationTitle("Syllabus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.body.weight(.semibold))
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private var summaryCard: some View {
        let counts = totals
        let progress = counts.total > 0 ? Double(counts.done) / Double(counts.total) : 0

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Overall progress")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(counts.done) / \(counts.total)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.accentColor)
            }

            ProgressView(value: progress)
                .tint(Color.accentColor)

            Text("\(max(counts.total - counts.done, 0)) items left across \(subjectsList.count) subjects")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .medxCard()
    }

    private func toggleCell(subject: String, field: TrackerField, currentValue: Bool) {
        let cellKey = "\(subject).\(field.rawValue)"
        savingCell = cellKey
        errorMessage = nil
        HapticManager.selection()

        // Optimistic local flip.
        if var subjects = trackerDoc?.subjects, var fields = subjects[subject] {
            fields.setValue(!currentValue, for: field)
            subjects[subject] = fields
            trackerDoc = UserTrackerDoc(subjects: subjects)
        }

        Task {
            do {
                let token = try await AuthService.shared.getValidIdToken()
                try await FirestoreService.shared.updateTrackerCell(
                    uid: uid,
                    subject: subject,
                    field: field,
                    value: !currentValue,
                    idToken: token
                )
                savingCell = nil
            } catch {
                errorMessage = "Couldn't sync \(subject) · \(field.label). Check your connection."
                savingCell = nil
                HapticManager.error()

                // Roll the optimistic flip back so the matrix never claims a save that
                // did not happen.
                if var subjects = trackerDoc?.subjects, var fields = subjects[subject] {
                    fields.setValue(currentValue, for: field)
                    subjects[subject] = fields
                    trackerDoc = UserTrackerDoc(subjects: subjects)
                }
            }
        }
    }
}

private struct SubjectTrackerRow: View {
    let subjectName: String
    let fields: SubjectTrackerFields
    let isSaving: Bool
    let onToggle: (TrackerField, Bool) -> Void

    private var done: Int {
        TrackerField.allCases.filter { fields.value(for: $0) == true }.count
    }

    private var tracked: Int {
        TrackerField.allCases.filter { fields.value(for: $0) != nil }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(subjectName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                if isSaving {
                    ProgressView()
                        .controlSize(.mini)
                } else if tracked > 0 {
                    Text("\(done)/\(tracked)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(done == tracked ? MedxTheme.successGreen : .secondary)
                }
            }

            HStack(spacing: 6) {
                ForEach(TrackerField.allCases) { field in
                    cell(field)
                }
            }
        }
        .padding(14)
        .medxCard(cornerRadius: 14)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(subjectName)
    }

    private func cell(_ field: TrackerField) -> some View {
        let value = fields.value(for: field)
        let isTracked = value != nil
        let isChecked = value == true

        return Button {
            guard isTracked else { return }
            onToggle(field, isChecked)
        } label: {
            VStack(spacing: 3) {
                Text(field.label)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Image(systemName: isChecked ? "checkmark" : (isTracked ? "circle" : "minus"))
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(isChecked ? Color.white : (isTracked ? Color.primary : Color.secondary.opacity(0.45)))
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isChecked ? Color.accentColor : (isTracked ? MedxSurface.fieldFill : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(
                        isTracked ? Color.clear : MedxSurface.separator.opacity(0.4),
                        lineWidth: MedxSurface.hairline
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isTracked)
        .accessibilityLabel(field.label)
        .accessibilityValue(isTracked ? (isChecked ? "Done" : "Not done") : "Not tracked")
        .accessibilityAddTraits(isChecked ? [.isSelected] : [])
    }
}

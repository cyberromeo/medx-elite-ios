import SwiftUI

/// The 23-subject × 6-stage revision matrix, pushed from Home. Written straight to Firestore
/// per cell, with the local value flipped first so the tap feels instant and rolled back if the
/// write fails. Still called a sheet, because Home has called it that since it was one.
public struct SyllabusTrackerSheet: View {
    public let uid: String
    @Binding public var trackerDoc: UserTrackerDoc?

    @State private var savingCell: String?
    @State private var errorMessage: String?

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
        let counts = totals

        List {
            Section {
                summary(counts)
            } footer: {
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(MedxOutcome.wrong)
                }
            }

            if subjectsList.isEmpty {
                Section {
                    MedxEmptyState(
                        "No checklist yet",
                        symbol: MedxFeature.syllabus.symbol,
                        message: "Your syllabus matrix appears here once it has been set up on your account."
                    )
                }
            } else {
                Section {
                    ForEach(subjectsList, id: \.name) { subject in
                        SubjectTrackerRow(
                            subjectName: subject.name,
                            fields: subject.fields,
                            isSaving: savingCell?.hasPrefix(subject.name) == true
                        ) { field, currentValue in
                            toggleCell(subject: subject.name, field: field, currentValue: currentValue)
                        }
                    }
                } header: {
                    Text("Subjects")
                } footer: {
                    Text("Videos, two revision cycles, PYQs, revision videos and QBank, per subject. Tap a cell to tick it.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(MedxFeature.syllabus.title)
        .navigationSubtitle("\(counts.done) of \(counts.total) ticked")
        .navigationBarTitleDisplayMode(.large)
    }

    private func summary(_ counts: (done: Int, total: Int)) -> some View {
        let fraction = counts.total > 0 ? Double(counts.done) / Double(counts.total) : 0

        return HStack(spacing: MedxSpace.l) {
            MedxRing(fraction: fraction, tint: MedxTheme.accent) {
                VStack(spacing: 0) {
                    MedxFigure("\(MedxFormat.percent(counts.done, of: counts.total))%", style: .title3)
                    Text("done")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 72, height: 72)

            VStack(alignment: .leading, spacing: MedxSpace.xs) {
                Text("\(MedxFormat.ratio(counts.done, of: counts.total)) ticked")
                    .font(.headline)
                Text("\(max(counts.total - counts.done, 0)) left across \(subjectsList.count) subjects")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, MedxSpace.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Overall progress")
        .accessibilityValue("\(counts.done) of \(counts.total) ticked")
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

    @Environment(\.colorScheme) private var scheme

    private var done: Int {
        TrackerField.allCases.filter { fields.value(for: $0) == true }.count
    }

    private var tracked: Int {
        TrackerField.allCases.filter { fields.value(for: $0) != nil }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MedxSpace.s) {
            HStack(spacing: MedxSpace.s) {
                Text(subjectName)
                    .font(.body.weight(.semibold))

                Spacer(minLength: MedxSpace.s)

                if isSaving {
                    ProgressView()
                        .controlSize(.mini)
                } else if tracked > 0 {
                    Text("\(done)/\(tracked)")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(done == tracked ? MedxOutcome.correct : Color.secondary)
                }
            }

            HStack(spacing: 6) {
                ForEach(TrackerField.allCases) { field in
                    cell(field)
                }
            }
        }
        .padding(.vertical, MedxSpace.xs)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(subjectName)
    }

    private func cell(_ field: TrackerField) -> some View {
        let value = fields.value(for: field)
        let isTracked = value != nil
        let isChecked = value == true
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

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
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(cellInk(isChecked: isChecked, isTracked: isTracked))
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(cellFill(isChecked: isChecked, isTracked: isTracked), in: shape)
            .contentShape(shape)
        }
        // Six buttons share one row: borderless keeps each one its own tap target.
        .buttonStyle(.borderless)
        .disabled(!isTracked)
        .accessibilityLabel(field.label)
        .accessibilityValue(isTracked ? (isChecked ? "Done" : "Not done") : "Not tracked")
        .accessibilityAddTraits(isChecked ? [.isSelected] : [])
    }

    private func cellInk(isChecked: Bool, isTracked: Bool) -> Color {
        if isChecked { return MedxTheme.accent.medxInkOnFill(in: scheme) }
        return isTracked ? Color.primary : Color.secondary
    }

    private func cellFill(isChecked: Bool, isTracked: Bool) -> Color {
        if isChecked { return MedxTheme.accent }
        return isTracked ? Color(uiColor: .tertiarySystemFill) : Color.clear
    }
}

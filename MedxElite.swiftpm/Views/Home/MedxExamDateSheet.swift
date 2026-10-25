import SwiftUI

/// Name and date of the exam being counted down to, from a tap on Home's countdown. Writing
/// them republishes the shared snapshot, so the widgets follow immediately.
struct MedxExamDateSheet: View {
    @ObservedObject private var stats = MedxStudyStatsStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            List {
                Section("Exam") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.characters)

                    DatePicker(
                        "Date",
                        selection: $date,
                        in: Date()...,
                        displayedComponents: .date
                    )
                }

                Section {
                    LabeledContent {
                        Text(MedxFormat.days(MedxDates.daysUntil(date)))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    } label: {
                        Label("Time left", systemImage: "calendar")
                    }
                } footer: {
                    Text("Home, the Home Screen widgets and the Lock Screen use this too.")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Exam countdown")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                name = stats.examName
                date = stats.examDate
            }
        }
        .medxTaskSheet()
    }

    private func save() {
        HapticManager.success()
        stats.examName = name.trimmingCharacters(in: .whitespaces)
        stats.examDate = date
        dismiss()
    }
}

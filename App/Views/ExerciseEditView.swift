import SwiftUI
import WorkoutLoggerCore
import WorkoutLoggerApp

/// Add or edit one Exercise: canonical name plus an editable alias list. Save
/// is disabled for a blank name; `SettingsModel` rejects duplicates and the
/// view surfaces that as an inline message. Same `.cancellationAction` /
/// `.confirmationAction` toolbar pair as `SetEditView`.
struct ExerciseEditView: View {
    let model: SettingsModel
    /// `nil` → adding a new Exercise; non-`nil` → editing this one.
    let existing: Exercise?

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var aliases: [String]
    @State private var errorText: String?

    init(model: SettingsModel, existing: Exercise?) {
        self.model = model
        self.existing = existing
        _name = State(initialValue: existing?.name ?? "")
        _aliases = State(initialValue: existing?.aliases ?? [])
    }

    var body: some View {
        Form {
            Section("Name") {
                TextField("Exercise name", text: $name)
            }
            Section("Aliases") {
                ForEach(aliases.indices, id: \.self) { i in
                    TextField("Alias", text: $aliases[i])
                }
                .onDelete { aliases.remove(atOffsets: $0) }
                Button("Add alias") { aliases.append("") }
            }
            if let errorText {
                Text(errorText).font(.footnote).foregroundStyle(.red)
            }
        }
        .navigationTitle(existing == nil ? "New Exercise" : "Edit Exercise")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func save() {
        let cleaned = aliases
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        do {
            if let existing {
                try model.updateExercise(named: existing.name, toName: name, aliases: cleaned)
            } else {
                try model.addExercise(name: name, aliases: cleaned)
            }
            dismiss()
        } catch {
            errorText = "That name is empty or already used."
        }
    }
}

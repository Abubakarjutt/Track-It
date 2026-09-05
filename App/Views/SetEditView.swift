import SwiftUI
import WorkoutLoggerCore

/// Edit one recorded set: load, reps, role, grouping (clear-to-straight or mark
/// dropset only — see spec Out of Scope), note, and an optional move to another
/// exercise. Builds a `LoggedSet` and hands it back; deletion is a separate
/// callback.
struct SetEditView: View {
    struct Result { var set: LoggedSet; var moveToExerciseName: String? }

    let set: LoggedSet
    let exerciseNames: [String]
    let unit: MassUnit
    let onSave: (Result) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var loadText: String
    @State private var reps: Int
    @State private var role: SetRole
    @State private var isDropset: Bool
    @State private var note: String
    @State private var moveTarget: String

    init(set: LoggedSet, exerciseNames: [String], unit: MassUnit,
         onSave: @escaping (Result) -> Void, onDelete: @escaping () -> Void) {
        self.set = set
        self.exerciseNames = exerciseNames
        self.unit = unit
        self.onSave = onSave
        self.onDelete = onDelete
        let shownLoad = set.loadKilograms.map { unit == .pounds ? $0 / 0.45359237 : $0 }
        _loadText = State(initialValue: shownLoad.map { String(($0 * 10).rounded() / 10) } ?? "")
        _reps = State(initialValue: set.reps ?? 0)
        _role = State(initialValue: set.role)
        _isDropset = State(initialValue: set.grouping == .dropset)
        _note = State(initialValue: set.note ?? "")
        _moveTarget = State(initialValue: "")
    }

    var body: some View {
        Form {
            Section("Load (\(unit == .pounds ? "lb" : "kg"))") {
                TextField("Load", text: $loadText).keyboardType(.decimalPad)
            }
            Section("Reps") {
                Stepper("\(reps)", value: $reps, in: 0...99)
            }
            Section("Role") {
                Picker("Role", selection: $role) {
                    Text("Working").tag(SetRole.working)
                    Text("Warm-up").tag(SetRole.warmup)
                }.pickerStyle(.segmented)
            }
            Section("Grouping") {
                Toggle("Dropset", isOn: $isDropset)
                if set.grouping == .superset {
                    Text("Part of a superset — saving clears that.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section("Note") {
                TextField("Note", text: $note, axis: .vertical)
            }
            Section("Move to exercise") {
                Picker("Exercise", selection: $moveTarget) {
                    Text("Keep here").tag("")
                    ForEach(exerciseNames, id: \.self) { Text($0).tag($0) }
                }
            }
            Section {
                Button("Delete set", role: .destructive) { onDelete(); dismiss() }
            }
        }
        .navigationTitle("Edit set")
        .toolbar {
            // Swipe-to-dismiss already discards unsaved edits, but ios.md
            // calls for an explicit Cancel/Done pair — relying on the swipe
            // alone leaves no on-screen affordance for it.
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save(); dismiss() }
            }
        }
    }

    private func save() {
        let enteredKg: Double? = Double(loadText).map { unit == .pounds ? $0 * 0.45359237 : $0 }
        var edited = set
        edited.loadKilograms = enteredKg
        edited.reps = edited.effort == .reps ? reps : edited.reps
        edited.role = role
        edited.grouping = isDropset ? .dropset : .straight
        edited.supersetRunID = isDropset ? edited.supersetRunID : nil
        edited.note = note.isEmpty ? nil : note
        onSave(Result(set: edited, moveToExerciseName: moveTarget.isEmpty ? nil : moveTarget))
    }
}

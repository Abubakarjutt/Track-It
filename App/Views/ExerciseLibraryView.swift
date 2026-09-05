import SwiftUI
import WorkoutLoggerApp

/// The full Exercise library: a stock list, "+" to add, tap to edit, swipe to
/// delete. Past workouts embed their `Exercise` by value, so an edit here
/// never changes recorded history.
struct ExerciseLibraryView: View {
    let model: SettingsModel
    @State private var adding = false

    var body: some View {
        List {
            ForEach(model.exercises, id: \.name) { exercise in
                NavigationLink {
                    ExerciseEditView(model: model, existing: exercise)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(exercise.name)
                        if !exercise.aliases.isEmpty {
                            Text(exercise.aliases.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .onDelete { offsets in
                for i in offsets { model.deleteExercise(named: model.exercises[i].name) }
            }
        }
        .navigationTitle("Exercise Library")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { adding = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $adding) {
            NavigationStack { ExerciseEditView(model: model, existing: nil) }
        }
        .safeAreaInset(edge: .bottom) {
            Text("Deleting an exercise leaves past workouts unchanged.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding()
        }
    }
}

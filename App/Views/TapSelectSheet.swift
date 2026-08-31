import SwiftUI
import WorkoutLoggerCore

/// Shown when voice could not place an exercise. Picking one re-issues the
/// utterance against it; dismissing without a choice leaves the workout untouched.
struct TapSelectSheet: View {
    let candidates: [Exercise]
    let onPick: (Exercise) -> Void

    var body: some View {
        NavigationStack {
            List(candidates, id: \.name) { exercise in
                Button(exercise.name) { onPick(exercise) }
            }
            .navigationTitle("Did you mean…")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}

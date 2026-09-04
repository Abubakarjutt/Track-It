import SwiftUI

/// Swipe-up list of every set for the current entry. Tap a row to edit it,
/// swipe to delete. Row order matches the active entry's set order 1:1.
struct SetListSheet: View {
    let lines: [String]
    let onEdit: (Int) -> Void
    let onDelete: (Int) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    Button { onEdit(index) } label: {
                        Text(line).font(.body.monospacedDigit())
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { onDelete(index) }
                    }
                }
            }
            .navigationTitle("This exercise")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

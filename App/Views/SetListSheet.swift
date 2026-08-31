import SwiftUI

/// Swipe-up list of every set logged for the current entry. Read-only in v1 C;
/// inline editing is subsystem D.
struct SetListSheet: View {
    let lines: [String]

    var body: some View {
        NavigationStack {
            List(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line).font(.body.monospacedDigit())
            }
            .navigationTitle("This exercise")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

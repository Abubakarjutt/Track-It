import SwiftUI
import WorkoutLoggerApp

/// The queued failed utterances, one per row, each with a Submit and a Discard.
/// A phrase leaves the device only on the Submit tap — submitting or discarding
/// both remove the row, so the list reflects only what is still undecided. Stock
/// `List`, matching the deliberately plain post-workout review screens.
struct RecognitionReviewView: View {
    let model: SettingsModel

    var body: some View {
        Group {
            if model.pendingUtterances.isEmpty {
                ContentUnavailableView {
                    Label("No phrases queued", systemImage: "mic.slash")
                 } description: {
                  Text("Failed sets appear here when recognition review is on. "
                        + "Submit a transcript to help, or discard it.")
                  }
              } else {
                List(model.pendingUtterances) { utterance in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(utterance.transcript)
                            .font(.body)
                            .foregroundStyle(.primary)
                        HStack(spacing: 16) {
                            Button("Discard", role: .destructive) {
                                model.discardPhrases([utterance])
                              }
                            Spacer()
                            Button("Submit") {
                                model.submitPhrases([utterance])
                              }
                              .fontWeight(.semibold)
                              }
                          }
                        }
                    }
                }
        }
        .navigationTitle("Review Phrases")
        .navigationBarTitleDisplayMode(.inline)
    }
}

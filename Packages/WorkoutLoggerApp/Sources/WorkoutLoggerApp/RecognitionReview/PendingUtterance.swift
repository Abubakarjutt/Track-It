import Foundation

/// One failed utterance sitting in the local review queue. By construction it
/// holds nothing but the transcript text and when it was captured — no audio,
/// no hypotheses, no fact about the workout it happened in.
public struct PendingUtterance: Equatable, Sendable, Identifiable {
    public let id: String
    public let transcript: String
    public let capturedAt: Date

    public init(id: String = UUID().uuidString, transcript: String, capturedAt: Date = Date()) {
        self.id = id
        self.transcript = transcript
        self.capturedAt = capturedAt
     }
}

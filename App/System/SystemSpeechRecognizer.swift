import Foundation
import Speech
import AVFoundation
import WorkoutLoggerApp

/// Real push-to-talk speech capture: on-device `SFSpeechRecognizer` over an
/// `AVAudioEngine` tap. `endUtterance()` stops the tap, waits for the final
/// result, and returns its transcriptions as the n-best list.
///
/// Isolation (ruling from Task 7's fix round): `TranscriptSource` is
/// `@MainActor`-isolated, so this class is `@MainActor` and `endUtterance()` is
/// `@MainActor async`. `SFSpeechRecognizer.recognitionTask`'s result handler is
/// `@Sendable` and runs off the main actor, so it must not touch this actor's
/// state directly. It pulls the Sendable payload it needs out of the
/// non-Sendable `SFSpeechRecognitionResult` first, then hops back with
/// `Task { @MainActor in ... }` to call `finish`, which resumes the stored
/// continuation on the main actor. This file is not compiled in this
/// environment; the hop is deliberately explicit rather than clever.
@MainActor
final class SystemSpeechRecognizer: TranscriptSource {
    /// A Sendable error wrapper so the off-main result handler can carry a
    /// failure across the actor hop without moving a non-Sendable `any Error`.
    private struct RecognitionFailure: Error {
        let message: String
    }

    private let recognizer = SFSpeechRecognizer()
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var continuation: CheckedContinuation<[String], Error>?

    func beginUtterance() {
        SFSpeechRecognizer.requestAuthorization { _ in }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try? session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.taskHint = .dictation
        self.request = request

        let input = audioEngine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
            request.append(buffer)
        }
        audioEngine.prepare()
        try? audioEngine.start()

        task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result, result.isFinal {
                let hypotheses = result.transcriptions.map(\.formattedString)
                let payload = hypotheses.isEmpty
                    ? [result.bestTranscription.formattedString]
                    : hypotheses
                Task { @MainActor in self.finish(.success(payload)) }
            } else if let error {
                let message = error.localizedDescription
                Task { @MainActor in self.finish(.failure(RecognitionFailure(message: message))) }
            }
        }
    }

    func endUtterance() async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
            request?.endAudio()
        }
    }

    private func finish(_ outcome: Result<[String], Error>) {
        continuation?.resume(with: outcome)
        continuation = nil
        task = nil
        request = nil
    }
}

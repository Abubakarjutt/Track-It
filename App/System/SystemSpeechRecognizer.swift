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
///
/// Hang-path guards (final fix wave F7): four paths used to park a
/// `CheckedContinuation` that nothing would ever resume — an unsupported locale
/// (`SFSpeechRecognizer()` is `nil`), a final result that lands before
/// `endUtterance()`, a stray second `released()`, and a second `released()` that
/// races the first before `finish` clears it. `endUtterance()` now resolves
/// immediately in each of those cases instead of awaiting a task that will never
/// end.
@MainActor
final class SystemSpeechRecognizer: TranscriptSource {
    /// A Sendable error wrapper so the off-main result handler can carry a
    /// failure across the actor hop without moving a non-Sendable `any Error`.
    private struct RecognitionFailure: Error {
        let message: String

        /// The recogniser could not be created for the current locale/device,
        /// so this utterance can never produce a transcript.
        static let unavailable = RecognitionFailure(
            message: "Speech recognition is unavailable on this device."
        )
    }

    private let recognizer = SFSpeechRecognizer()
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var continuation: CheckedContinuation<[String], Error>?
    /// Set when `beginUtterance()` bailed because there is no recogniser; the
    /// next `endUtterance()` fails fast rather than awaiting a task that was
    /// never started.
    private var pendingUnavailable = false

    func beginUtterance() {
        guard recognizer != nil else {
            pendingUnavailable = true
            return
        }

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
            // No recogniser was available at press time — fail fast.
            if pendingUnavailable {
                pendingUnavailable = false
                continuation.resume(throwing: RecognitionFailure.unavailable)
                return
            }
            // Nothing in flight: either the final result already arrived and
            // `finish` cleared everything, or this is a stray second release.
            // There is no task to stop and no result to wait for.
            if task == nil, request == nil {
                continuation.resume(returning: [])
                return
            }
            // A capture is running but a continuation is already parked — a
            // second release raced the first. Resolve this one empty rather
            // than overwrite (and strand) the first.
            if self.continuation != nil {
                continuation.resume(returning: [])
                return
            }
            // A real capture is running — park the continuation for `finish`
            // and stop the engine so the recogniser emits its final result.
            self.continuation = continuation
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
            request?.endAudio()
        }
    }

    private func finish(_ outcome: Result<[String], Error>) {
        // Resume at most once: a result arriving before `endUtterance()` parked
        // a continuation must not later double-resume it.
        guard let continuation else {
            task = nil
            request = nil
            return
        }
        continuation.resume(with: outcome)
        self.continuation = nil
        task = nil
        request = nil
    }
}

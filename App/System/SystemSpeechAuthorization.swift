import Foundation
import Speech
import AVFoundation
import WorkoutLoggerApp

/// `SpeechAuthorization` over `SFSpeechRecognizer` + `AVAudioApplication`. A
/// thin adapter: it only flattens the two system enums into the four states
/// the UI distinguishes. Not compiled in this environment.
@MainActor
final class SystemSpeechAuthorization: SpeechAuthorization {
    var status: SpeechAuthorizationStatus {
        guard SFSpeechRecognizer() != nil else { return .unavailable }
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            switch AVAudioApplication.shared.recordPermission {
            case .granted: return .granted
            case .denied: return .denied
            default: return .notDetermined
            }
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
    }

    func request() async {
        // Both system callbacks fire on an arbitrary background queue. Because
        // this type is `@MainActor`, Swift 6 would otherwise infer the closures
        // as main-actor-isolated and trap on `dispatch_assert_queue` when the
        // SDK runs them off-main. `@Sendable` keeps them non-isolated; resuming
        // a `CheckedContinuation` is thread-safe and touches no isolated state.
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            SFSpeechRecognizer.requestAuthorization { @Sendable _ in cont.resume() }
        }
        _ = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { @Sendable granted in
                cont.resume(returning: granted)
            }
        }
    }
}

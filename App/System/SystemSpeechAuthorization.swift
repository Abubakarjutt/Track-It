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
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { _ in cont.resume() }
        }
        _ = await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { granted in cont.resume(returning: granted) }
        }
    }
}

import Foundation
import AVFoundation
import AudioToolbox
import WorkoutLoggerApp

/// Real readback: `AVSpeechSynthesizer` for spoken plans, a short system sound
/// for the earcon. `@MainActor` because `ReadbackVoice` is `@MainActor`-isolated
/// (Task 7).
@MainActor
final class SystemReadbackVoice: ReadbackVoice {
    private let synthesizer = AVSpeechSynthesizer()

    func perform(_ plan: ReadbackPlan) {
        switch plan {
        case .speak(let text):
            let utterance = AVSpeechUtterance(string: text)
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            synthesizer.speak(utterance)
        case .earcon:
            AudioServicesPlaySystemSound(1103)
        }
    }
}

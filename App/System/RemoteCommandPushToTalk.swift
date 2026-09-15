import Foundation
import MediaPlayer
import WorkoutLoggerApp

/// Lets a wired/Bluetooth headset remote button start and stop an utterance
/// without touching the screen (cluster 7b). A second caller of the same
/// `WorkoutSessionModel` seam `HUDView`'s talk button already drives — no
/// model API changes beyond `toggleListening()` (OPEN QUESTION 1).
///
/// A remote gives discrete taps, not a held state, so there is no "press and
/// hold" to map — `togglePlayPauseCommand` alone is registered (OPEN
/// QUESTION 1: most single-button remotes only ever send toggle/play-pause,
/// so separate `playCommand`/`pauseCommand` targets would rarely see
/// independent signal). Reliable command delivery needs an active Now
/// Playing entry, so this type also publishes/clears minimal
/// `MPNowPlayingInfoCenter` info for the duration of an active workout
/// (OPEN QUESTION 2) — presentation-layer plumbing, which is why it's owned
/// here and not by `WorkoutSessionModel`.
///
/// `@MainActor` because `WorkoutSessionModel` is `@MainActor`-isolated and
/// because `MPRemoteCommandCenter`/`MPNowPlayingInfoCenter` are main-actor
/// APIs anyway.
@MainActor
final class RemoteCommandPushToTalk {
    private let session: WorkoutSessionModel
    private let commandCenter: MPRemoteCommandCenter
    private let nowPlayingInfoCenter: MPNowPlayingInfoCenter

    init(
        session: WorkoutSessionModel,
        commandCenter: MPRemoteCommandCenter = .shared(),
        nowPlayingInfoCenter: MPNowPlayingInfoCenter = .default()
    ) {
        self.session = session
        self.commandCenter = commandCenter
        self.nowPlayingInfoCenter = nowPlayingInfoCenter

        commandCenter.togglePlayPauseCommand.isEnabled = true
        // `[weak self]` is load-bearing, not defensive: `commandCenter` is a
        // process-wide singleton, so a strong-self target would retain this
        // instance forever. Swift infers this closure @MainActor because it's
        // formed inside a @MainActor init, but MediaPlayer — not the
        // compiler — is what actually guarantees the callback lands on the
        // main thread; that's a documented framework contract, not something
        // isolation-checking proved here.
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.session.toggleListening()
            return .success
        }

        observeActiveWorkout()
    }

    /// Re-arms a `withObservationTracking` watch on `session.hasActiveWorkout`
    /// after every fire — the closure-based API only fires once per
    /// registration — and syncs Now Playing info to match on both the
    /// initial call and every subsequent transition.
    private func observeActiveWorkout() {
        withObservationTracking {
            _ = session.hasActiveWorkout
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.syncNowPlayingInfo()
                self?.observeActiveWorkout()
            }
        }
        syncNowPlayingInfo()
    }

    private func syncNowPlayingInfo() {
        nowPlayingInfoCenter.nowPlayingInfo = session.hasActiveWorkout
            ? [MPMediaItemPropertyTitle: "Trackit — workout in progress"]
            : nil
    }
}

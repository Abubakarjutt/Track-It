/// Current speech / microphone authorization, flattened to the four states
/// the UI distinguishes. `unavailable` means the device or locale has no
/// on-device recogniser — iOS Settings can't fix it, so no recovery link.
public enum SpeechAuthorizationStatus: Equatable, Sendable {
    case notDetermined
    case granted
    case denied
    case unavailable
}

/// Reads and requests speech authorization. The real implementation wraps
/// the system speech + record-permission APIs and carries no logic; a
/// scriptable fake drives the model tests.
@MainActor
public protocol SpeechAuthorization: AnyObject {
    var status: SpeechAuthorizationStatus { get }
    func request() async
}

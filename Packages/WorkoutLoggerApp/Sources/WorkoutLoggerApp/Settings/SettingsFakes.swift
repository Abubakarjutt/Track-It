import WorkoutLoggerCore

/// In-memory `SettingsStore` for tests and previews.
public final class InMemorySettingsStore: SettingsStore {
    public var defaultUnit: MassUnit
    public var hasCompletedOnboarding: Bool

    public init(defaultUnit: MassUnit = .kilograms, hasCompletedOnboarding: Bool = false) {
        self.defaultUnit = defaultUnit
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }
}

/// Scriptable `SpeechAuthorization`: starts at `status`, and `request()`
/// moves it to `resultAfterRequest` and bumps `requestCount`.
@MainActor
public final class FakeSpeechAuthorization: SpeechAuthorization {
    public private(set) var status: SpeechAuthorizationStatus
    public private(set) var requestCount = 0
    private let resultAfterRequest: SpeechAuthorizationStatus

    public init(
        status: SpeechAuthorizationStatus = .notDetermined,
        resultAfterRequest: SpeechAuthorizationStatus = .granted
    ) {
        self.status = status
        self.resultAfterRequest = resultAfterRequest
    }

    public func request() async {
        requestCount += 1
        status = resultAfterRequest
    }

    /// Test hook: simulate the user changing the setting in iOS Settings.
    public func set(_ status: SpeechAuthorizationStatus) {
        self.status = status
    }
}

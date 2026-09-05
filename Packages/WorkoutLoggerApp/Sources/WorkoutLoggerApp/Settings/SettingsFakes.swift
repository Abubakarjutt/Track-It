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

/// In-memory `ExerciseLibraryStore` with the same validation rules as the
/// SwiftData one, for model tests and previews.
public final class InMemoryExerciseLibraryStore: ExerciseLibraryStore {
    private var items: [Exercise] = []
    public init() {}

    public func all() -> [Exercise] {
        items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func seedIfEmpty(_ exercises: [Exercise]) {
        guard items.isEmpty else { return }
        items = exercises
    }

    public func add(_ exercise: Exercise) throws {
        let name = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ExerciseLibraryError.emptyName }
        guard !items.contains(where: {
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }) else { throw ExerciseLibraryError.duplicateName }
        items.append(Exercise(name: name, aliases: exercise.aliases))
    }

    public func update(named originalName: String, to exercise: Exercise) throws {
        let name = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ExerciseLibraryError.emptyName }
        guard let index = items.firstIndex(where: {
            $0.name.localizedCaseInsensitiveCompare(originalName) == .orderedSame
        }) else { return }
        let collides = items.enumerated().contains { offset, item in
            offset != index && item.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }
        guard !collides else { throw ExerciseLibraryError.duplicateName }
        items[index] = Exercise(name: name, aliases: exercise.aliases)
    }

    public func delete(named name: String) {
        items.removeAll { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }
}

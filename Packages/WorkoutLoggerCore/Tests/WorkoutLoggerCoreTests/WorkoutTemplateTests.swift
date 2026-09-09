import Foundation
import Testing
import WorkoutLoggerCore

@Suite("Workout templates")
struct WorkoutTemplateTests {

    private let bench = Exercise(name: "Bench", aliases: ["bench"])
    private let squat = Exercise(name: "Squat", aliases: ["squat"])

    /// A not-yet-ended workout with one squat working set already logged — the
    /// shape every resume test below starts from. `templateName` is stamped on
    /// unless left nil (a plain, untemplated workout the lifter forgot to end).
    private func staleSquatWorkout(templateName: String? = nil) -> Workout {
        Workout(
            entries: [Entry(exercise: squat, sets: [
                LoggedSet(
                    loadType: .external, effort: .reps, role: .working,
                    grouping: .straight, loadKilograms: 140, reps: 5,
                    loggedAt: Date(timeIntervalSince1970: 1)
                ),
            ])],
            startedAt: Date(timeIntervalSince1970: 0),
            templateName: templateName
        )
    }

    @Test("a template item carries an optional planned set count")
    func templateItemCarriesPlannedSets() {
        let item = TemplateItem(exercise: bench, plannedSets: 4, restTargetSeconds: 180)
        #expect(item.plannedSets == 4)
        #expect(TemplateItem(exercise: bench).plannedSets == nil)
    }

    @Test("starting from a template opens a fresh workout without pre-creating entries")
    func startFromTemplateCreatesNoEntries() {
        let store = InMemoryWorkoutStore()
        let engine = WorkoutEngine(store: store, library: ExerciseLibrary([bench, squat]))
        let template = WorkoutTemplate(name: "Push", items: [
            TemplateItem(exercise: bench, restTargetSeconds: 180),
            TemplateItem(exercise: squat),
        ])

        engine.startWorkout(from: template)

        #expect(engine.workout?.isEnded == false)
        #expect(engine.workout?.entries.isEmpty == true)
    }

    @Test("a workout started from a template records the template's name, and persists it")
    func templateIdentityRecorded() {
        let store = InMemoryWorkoutStore()
        let engine = WorkoutEngine(store: store, library: ExerciseLibrary([bench]))
        engine.startWorkout(from: WorkoutTemplate(name: "Push Day", items: [TemplateItem(exercise: bench)]))
        #expect(engine.workout?.templateName == "Push Day")
        #expect(store.saved.last?.templateName == "Push Day")   // the persisted revision carries it
    }

    @Test("a plain workout has no template name")
    func plainStartHasNoTemplateName() {
        let store = InMemoryWorkoutStore()
        let engine = WorkoutEngine(store: store, library: .empty)
        engine.startWorkout()
        #expect(engine.workout?.templateName == nil)
    }

    @Test("a template whose name is blank leaves templateName nil, not an empty string")
    func blankTemplateNameIsNil() {
        let store = InMemoryWorkoutStore()
        let engine = WorkoutEngine(store: store, library: ExerciseLibrary([bench]))
        engine.startWorkout(from: WorkoutTemplate(name: "   ", items: [TemplateItem(exercise: bench)]))
        #expect(engine.workout?.templateName == nil)
    }

    @Test("resuming a templated workout keeps its template name")
    func resumePreservesTemplateName() {
        let store = InMemoryWorkoutStore()
        let engine = WorkoutEngine(store: store, library: .empty)
        engine.resume(Workout(startedAt: Date(timeIntervalSince1970: 1), templateName: "Push Day"))
        #expect(engine.workout?.templateName == "Push Day")
        #expect(store.saved.last?.templateName == "Push Day")
    }

    @Test("the current rest target follows the active exercise's armed value, else the default")
    func templateRestTargetResolvesPerActiveExercise() {
        let store = InMemoryWorkoutStore()
        let engine = WorkoutEngine(store: store, library: ExerciseLibrary([bench, squat])) // default 120
        engine.startWorkout(from: WorkoutTemplate(name: "Lower", items: [
            TemplateItem(exercise: squat, restTargetSeconds: 210),
            TemplateItem(exercise: bench), // armed, but no target of its own
        ]))

        engine.hear(["squat"])
        engine.hear(["140 for 5"])
        #expect(engine.currentRestTargetSeconds == 210)

        engine.hear(["bench"])
        engine.hear(["100 for 5"])
        #expect(engine.currentRestTargetSeconds == 120)
    }

    @Test("the rest-done signal measures against the armed target, not the default")
    func templateRestTargetDrivesTheDoneSignal() {
        var clock = Date(timeIntervalSince1970: 0)
        let store = InMemoryWorkoutStore()
        let engine = WorkoutEngine(
            store: store, library: ExerciseLibrary([squat]),
            restTarget: 120, now: { clock } // default would fire at 120s
        )
        engine.startWorkout(from: WorkoutTemplate(name: "Lower", items: [
            TemplateItem(exercise: squat, restTargetSeconds: 210),
        ]))
        engine.hear(["squat"])
        clock = Date(timeIntervalSince1970: 100)
        engine.hear(["140 for 5"])

        clock = Date(timeIntervalSince1970: 250) // 150s of rest — past the default, short of 210
        #expect(engine.isRestTargetReached == false)

        clock = Date(timeIntervalSince1970: 320) // 220s of rest — past the armed 210
        #expect(engine.isRestTargetReached == true)
    }

    @Test("a plain start-workout after a templated one drops the armed rest targets")
    func plainStartClearsArmedTargets() {
        let store = InMemoryWorkoutStore()
        let engine = WorkoutEngine(store: store, library: ExerciseLibrary([squat]), restTarget: 120)
        engine.startWorkout(from: WorkoutTemplate(name: "Lower", items: [
            TemplateItem(exercise: squat, restTargetSeconds: 210),
        ]))

        engine.startWorkout() // a fresh untemplated session
        engine.hear(["squat"])
        engine.hear(["140 for 5"])

        #expect(engine.currentRestTargetSeconds == 120)
    }

    @Test("resuming a templated workout re-arms its rest targets via the template provider")
    func resumeReArmsRestTargetsFromTemplate() {
        let template = WorkoutTemplate(name: "Lower", items: [
            TemplateItem(exercise: squat, restTargetSeconds: 210),
        ])
        let store = InMemoryWorkoutStore()
        let engine = WorkoutEngine(
            store: store,
            library: ExerciseLibrary([squat]),
            restTarget: 120,
            templateProvider: { name in name == "Lower" ? template : nil }
        )

        // The lifter trained squats from "Lower", forgot to end the workout, and
        // the app is relaunching into it — only the template's name survives, on
        // the record, not the template value that armed the targets.
        engine.resume(staleSquatWorkout(templateName: "Lower"))

        // squat is the active exercise (its entry is last), so its armed 210
        // applies straight away — the lifter does not re-announce it.
        #expect(engine.currentRestTargetSeconds == 210)
    }

    @Test("resuming a workout whose template was deleted falls back to the engine default")
    func resumeWithUnresolvableTemplateFallsBackToDefault() {
        let store = InMemoryWorkoutStore()
        let engine = WorkoutEngine(
            store: store,
            library: ExerciseLibrary([squat]),
            restTarget: 120,
            templateProvider: { _ in nil } // the lifter deleted "Lower" between sessions
        )

        engine.resume(staleSquatWorkout(templateName: "Lower"))

        #expect(engine.currentRestTargetSeconds == 120)
    }

    @Test("resuming a plain workout never consults the template provider")
    func resumePlainWorkoutSkipsProvider() {
        var lookups: [String] = []
        let store = InMemoryWorkoutStore()
        let engine = WorkoutEngine(
            store: store,
            library: ExerciseLibrary([squat]),
            restTarget: 120,
            templateProvider: { name in lookups.append(name); return nil }
        )

        engine.resume(staleSquatWorkout()) // no templateName

        #expect(lookups.isEmpty)
        #expect(engine.currentRestTargetSeconds == 120)
    }

    @Test("a re-armed template target drives the rest-done signal after a resume")
    func resumeReArmedTargetDrivesDoneSignal() {
        var clock = Date(timeIntervalSince1970: 0)
        let template = WorkoutTemplate(name: "Lower", items: [
            TemplateItem(exercise: squat, restTargetSeconds: 210),
        ])
        let store = InMemoryWorkoutStore()
        let engine = WorkoutEngine(
            store: store,
            library: ExerciseLibrary([squat]),
            restTarget: 120, // default would fire at 120s
            templateProvider: { name in name == "Lower" ? template : nil },
            now: { clock }
        )
        engine.resume(staleSquatWorkout(templateName: "Lower"))

        // The resume reset the running rest period (story 20), so start one.
        clock = Date(timeIntervalSince1970: 100)
        engine.hear(["140 for 5"])

        clock = Date(timeIntervalSince1970: 250) // 150s rest — past default 120, short of 210
        #expect(engine.isRestTargetReached == false)

        clock = Date(timeIntervalSince1970: 320) // 220s rest — past the re-armed 210
        #expect(engine.isRestTargetReached == true)
    }

    @Test("an exercise the template never mentions uses the engine default")
    func unlistedExerciseUsesDefault() {
        let curl = Exercise(name: "Curl", aliases: ["curl"])
        let store = InMemoryWorkoutStore()
        let engine = WorkoutEngine(
            store: store, library: ExerciseLibrary([squat, curl]), restTarget: 120
        )
        engine.startWorkout(from: WorkoutTemplate(name: "Lower", items: [
            TemplateItem(exercise: squat, restTargetSeconds: 210),
        ]))

        engine.hear(["curl"]) // not in the template at all
        engine.hear(["20 for 12"])

        #expect(engine.currentRestTargetSeconds == 120)
    }
}

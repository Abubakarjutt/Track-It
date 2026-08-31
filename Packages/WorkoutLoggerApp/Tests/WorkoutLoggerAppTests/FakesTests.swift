import Testing
@testable import WorkoutLoggerApp

@Suite("Fakes")
struct FakesTests {

    @Test("scripted transcript source dequeues utterances in order, then empties")
    func scriptedDequeue() async throws {
        let source = ScriptedTranscriptSource([["start workout"], ["bench 100 for 5"]])

        source.beginUtterance()
        let first = try await source.endUtterance()
        let second = try await source.endUtterance()
        let third = try await source.endUtterance()

        #expect(first == ["start workout"])
        #expect(second == ["bench 100 for 5"])
        #expect(third == [])
        #expect(source.beganCount == 1)
    }

    @Test("scripted source can be told to throw once exhausted")
    func scriptedThrows() async {
        let source = ScriptedTranscriptSource([])
        source.throwWhenExhausted = true

        await #expect(throws: ScriptedTranscriptSource.Failure.self) {
            try await source.endUtterance()
        }
    }

    @Test("spies record what they were asked to do")
    func spiesRecord() {
        let voice = SpyReadbackVoice()
        let haptics = SpyHaptics()

        voice.perform(.speak("hi"))
        voice.perform(.earcon)
        haptics.play(.logged)

        #expect(voice.performed == [.speak("hi"), .earcon])
        #expect(haptics.played == [.logged])
    }
}

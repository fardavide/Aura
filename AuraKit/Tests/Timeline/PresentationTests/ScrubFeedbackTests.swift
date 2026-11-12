import Testing

@testable import TimelinePresentation

struct ScrubFeedbackTests {
    @Test func `given a drag when the track moves in small steps then feedback ticks after enough travel`() {
        // given
        var feedback = ScrubFeedback()
        feedback.begin(at: 300)

        // when
        let ticks = [296.0, 285.0, 272.0].map { position in
            feedback.move(to: position)
            return feedback.tick
        }

        // then
        #expect(ticks == [0, 0, 1])
    }

    @Test func `given a fast drag when the track moves again immediately then feedback waits before repeating`() {
        // given
        var feedback = ScrubFeedback()
        feedback.begin(at: 300)
        let now = ContinuousClock.now

        // when
        feedback.move(to: 330, at: now)
        let first = feedback.tick
        feedback.move(to: 390, at: now.advanced(by: .milliseconds(20)))
        let duringCooldown = feedback.tick
        feedback.move(to: 395, at: now.advanced(by: .milliseconds(90)))

        // then
        #expect([first, duringCooldown, feedback.tick] == [1, 1, 2])
    }

    @Test func `given a released drag when the track glides then feedback stays silent`() {
        // given
        var feedback = ScrubFeedback()
        feedback.begin(at: 300)
        feedback.end()

        // when
        feedback.move(to: 395)

        // then
        #expect(feedback.tick == 0)
    }
}

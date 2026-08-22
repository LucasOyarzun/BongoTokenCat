import Foundation
@testable import BongoKit

private func drumEvent(_ name: String, tool: String? = nil, text: String? = nil) -> HookEvent {
    HookEvent(hookEventName: name, sessionId: "s1", cwd: "/tmp/w", toolName: tool,
              agentType: nil, notificationType: nil, errorType: nil,
              messageText: text, lastAssistantMessage: nil)
}

@MainActor
func runDrumEngineTests() {
    suite("Drum engine") {
        test("does not drum for states that are not producing anything") {
            expectEqual(DrumEngine.burstDuration(for: drumEvent("UserPromptSubmit")), 0)
            expectEqual(DrumEngine.burstDuration(for: drumEvent("SessionEnd")), 0)
        }

        // Tool events carry no text. Measured on real sessions they land a median
        // 7.7s apart, so without this fallback a tool-only stretch shows a
        // motionless cat.
        test("falls back to a short burst when an event carries no text") {
            expectEqual(DrumEngine.burstDuration(for: drumEvent("PreToolUse", tool: "Bash")),
                        DrumEngine.toolBurst)
        }

        test("scales the burst with how much text was produced") {
            let tokens = 600
            let text = String(repeating: "a", count: tokens * 4)

            let burst = DrumEngine.burstDuration(for: drumEvent("MessageDisplay", text: text))

            expectClose(burst, Double(tokens) / DrumEngine.tokensPerSecond, tolerance: 0.01)
        }

        // A single very long turn must not pin the paws down for minutes after the
        // work is over.
        test("clamps a huge message to the maximum burst") {
            let text = String(repeating: "a", count: 500_000)

            expectEqual(DrumEngine.burstDuration(for: drumEvent("MessageDisplay", text: text)),
                        DrumEngine.maxBurst)
        }

        test("never produces a burst shorter than one visible hit") {
            expectEqual(DrumEngine.burstDuration(for: drumEvent("MessageDisplay", text: "hi")),
                        DrumEngine.toolBurst)
        }

        test("beats faster when more work is queued") {
            expect(DrumEngine.beatsPerSecond(remaining: DrumEngine.maxBurst)
                   > DrumEngine.beatsPerSecond(remaining: 0.2),
                   "a heavy turn should look more frantic than a single tool call")
        }

        test("estimates tokens from text length") {
            expectEqual(DrumEngine.estimatedTokens(in: String(repeating: "a", count: 400)), 100)
        }
    }
}

@MainActor
func runPawPositionTests() {
    suite("Paw pattern") {
        test("alternates paws across one cycle") {
            expectEqual(PawPosition.drumming(at: 0, beatsPerSecond: 1), PawPosition(left: .down, right: .up))
            expectEqual(PawPosition.drumming(at: 1, beatsPerSecond: 1), PawPosition(left: .up, right: .down))
        }

        // Without the gap the cat reads as frozen mid-slam rather than as playing.
        test("lifts both paws between strikes") {
            expectEqual(PawPosition.drumming(at: 0.75, beatsPerSecond: 1), .bothUp)
        }

        // Between bursts a working agent used to look exactly like an idle one.
        test("taps slowly between bursts instead of holding still") {
            expectEqual(PawPosition.idleTapping(at: 0), PawPosition(left: .down, right: .up))
            expectEqual(PawPosition.idleTapping(at: PawPosition.idleBeat), PawPosition(left: .up, right: .down))
        }

        test("spends most of an idle beat with both paws up") {
            expectEqual(PawPosition.idleTapping(at: PawPosition.idleStrike + 0.01), .bothUp)
            expect(PawPosition.idleStrike < PawPosition.idleBeat / 2,
                   "an idle tap must be a tap, not a lean")
        }

        test("rests paws down when asleep or failed") {
            expectEqual(PawPosition.resting(for: .sleeping), .bothDown)
            expectEqual(PawPosition.resting(for: .failed), .bothDown)
        }

        test("raises one paw when waiting on the user") {
            expectEqual(PawPosition.resting(for: .needsInput).left, .up)
        }

        test("names a distinct sprite per side and pose") {
            expectEqual(PawPose.up.spriteName(side: "left"), "paw-left-up")
            expectEqual(PawPose.down.spriteName(side: "right"), "paw-right-down")
        }
    }
}

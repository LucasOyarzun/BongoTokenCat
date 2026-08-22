import Foundation
@testable import BongoKit

private func registryEvent(_ name: String,
                           session: String,
                           tool: String? = nil,
                           text: String? = nil,
                           cwd: String? = "/Users/x/workspaces/tokyo") -> HookEvent {
    HookEvent(hookEventName: name, sessionId: session, cwd: cwd, toolName: tool,
              agentType: nil, notificationType: nil, errorType: nil,
              messageText: text, lastAssistantMessage: nil)
}

@MainActor
func runAgentRegistryTests() {
    suite("Agent registry") {
        test("tracks one agent per session") {
            let registry = AgentRegistry()

            registry.apply(registryEvent("PreToolUse", session: "a", tool: "Edit"))
            registry.apply(registryEvent("PreToolUse", session: "b", tool: "Bash"))

            expectEqual(registry.visibleAgents.count, 2)
        }

        test("ignores events it has no state for") {
            let registry = AgentRegistry()

            registry.apply(registryEvent("SomeFutureHook", session: "a"))

            expect(registry.visibleAgents.isEmpty, "an unmapped hook must not create an agent")
        }

        // Back-to-back turns should read as one continuous roll. Restarting the
        // burst on each event would clip the tail off every message.
        test("extends a burst rather than restarting it") {
            let registry = AgentRegistry()
            let now = Date()
            let long = String(repeating: "a", count: 4 * 600)

            registry.apply(registryEvent("MessageDisplay", session: "a", text: long), now: now)
            let afterLong = registry.agents["a"]?.drumsUntil

            registry.apply(registryEvent("PreToolUse", session: "a", tool: "Bash"), now: now)
            let afterShort = registry.agents["a"]?.drumsUntil

            expectEqual(afterLong, afterShort, "a short event must not cut a long burst short")
        }

        test("keeps the last known workspace when an event omits cwd") {
            let registry = AgentRegistry()
            registry.apply(registryEvent("PreToolUse", session: "a", tool: "Edit"))

            registry.apply(registryEvent("Stop", session: "a", cwd: nil))

            expectEqual(registry.agents["a"]?.workspaceInfo.directory, "tokyo")
        }

        test("reports the most urgent state for the single cat") {
            let registry = AgentRegistry()

            registry.apply(registryEvent("PreToolUse", session: "a", tool: "Edit"))
            registry.apply(registryEvent("StopFailure", session: "b"))

            expectEqual(registry.aggregateState, .failed)
        }

        test("orders agents stably so cats do not swap places") {
            let registry = AgentRegistry()

            registry.apply(registryEvent("PreToolUse", session: "z", tool: "Edit", cwd: "/w/alpha"))
            registry.apply(registryEvent("PreToolUse", session: "a", tool: "Edit", cwd: "/w/beta"))

            expectEqual(registry.visibleAgents.map(\.label), ["alpha", "beta"])
        }

        test("ages agents that stopped emitting") {
            let registry = AgentRegistry()
            let start = Date()
            registry.apply(registryEvent("PreToolUse", session: "a", tool: "Edit"), now: start)

            registry.decay(now: start.addingTimeInterval(StateDecay.toIdle + 1))

            expectEqual(registry.agents["a"]?.state, .idle)
        }

        test("drops sessions that have been asleep for a long time") {
            let registry = AgentRegistry()
            let start = Date()
            registry.apply(registryEvent("SessionEnd", session: "a"), now: start)

            registry.decay(now: start.addingTimeInterval(31 * 60))

            expect(registry.agents.isEmpty, "a dead session should stop taking up screen space")
        }

        test("keeps a live session through a decay pass") {
            let registry = AgentRegistry()
            let start = Date()
            registry.apply(registryEvent("PreToolUse", session: "a", tool: "Edit"), now: start)

            registry.decay(now: start.addingTimeInterval(31 * 60))

            expectEqual(registry.agents["a"]?.state, .sleeping,
                        "a quiet but never-ended session sleeps rather than vanishing")
        }

        test("clears a question once acknowledged") {
            let registry = AgentRegistry()
            registry.apply(registryEvent("Elicitation", session: "a"))

            registry.acknowledge("a")

            expectEqual(registry.agents["a"]?.state, .idle)
        }

        // The animation timer is the app's only recurring cost, so what turns it on
        // is worth pinning down.
        test("animates for a busy agent even with no burst left") {
            let registry = AgentRegistry()
            registry.apply(registryEvent("PreToolUse", session: "a", tool: "Edit"),
                           now: Date().addingTimeInterval(-60))

            expect(registry.needsAnimation, "a working agent taps between bursts")
        }

        test("stops animating once nothing is working") {
            let registry = AgentRegistry()
            registry.apply(registryEvent("Stop", session: "a"))

            expect(!registry.needsAnimation, "a finished agent holds a pose")
        }
    }
}

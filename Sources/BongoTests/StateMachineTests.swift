import Foundation
@testable import BongoKit

func makeEvent(_ name: String,
               session: String = "s1",
               tool: String? = nil,
               notification: String? = nil,
               text: String? = nil,
               cwd: String? = "/Users/x/workspaces/tokyo") -> HookEvent {
    HookEvent(hookEventName: name, sessionId: session, cwd: cwd, toolName: tool,
              agentType: nil, notificationType: notification, errorType: nil,
              messageText: text, lastAssistantMessage: nil)
}

@MainActor
func runEventMappingTests() {
    suite("Event mapping") {
        test("maps a tool call to working") {
            expectEqual(EventMapping.state(for: makeEvent("PreToolUse", tool: "Edit")), .working)
        }

        // A Task call is a subagent launch, which deserves its own state — otherwise
        // delegating looks identical to editing a file.
        test("maps a Task call to delegating") {
            expectEqual(EventMapping.state(for: makeEvent("PreToolUse", tool: "Task")), .delegating)
        }

        test("treats a completion notification as done, not as a question") {
            expectEqual(EventMapping.state(for: makeEvent("Notification", notification: "agent_completed")), .done)
        }

        test("treats other notifications as waiting for the user") {
            expectEqual(EventMapping.state(for: makeEvent("Notification", notification: "agent_needs_input")), .needsInput)
        }

        test("ignores hooks it does not know about") {
            expectEqual(EventMapping.state(for: makeEvent("SomeFutureHook")), nil)
        }

        test("derives the workspace name from cwd") {
            expectEqual(makeEvent("Stop", cwd: "/Users/x/workspaces/tokyo").workspace, "tokyo")
        }

        test("falls back to a placeholder workspace when cwd is missing") {
            expectEqual(makeEvent("Stop", cwd: nil).workspace, "unknown")
        }

        test("reads assistant text from either field it can arrive in") {
            let fromStop = HookEvent(hookEventName: "Stop", sessionId: "s", cwd: nil, toolName: nil,
                                     agentType: nil, notificationType: nil, errorType: nil,
                                     messageText: nil, lastAssistantMessage: "done")
            expectEqual(fromStop.producedText, "done")
            expectEqual(makeEvent("MessageDisplay", text: "hi").producedText, "hi")
        }
    }
}

@MainActor
func runStateDecayTests() {
    suite("State decay") {
        test("ages a quiet agent to idle") {
            expectEqual(StateDecay.decayed(.working, silentFor: StateDecay.toIdle + 1), .idle)
        }

        test("ages a long-quiet agent to sleeping") {
            expectEqual(StateDecay.decayed(.working, silentFor: StateDecay.toSleeping + 1), .sleeping)
        }

        // A question is still unanswered no matter how long it waits.
        test("never ages a state that is waiting on the user") {
            expectEqual(StateDecay.decayed(.needsInput, silentFor: StateDecay.toSleeping * 2), .needsInput)
        }

        // A result nobody read is a result nobody got. These hold until clicked.
        test("never ages a result the user has not seen") {
            expectEqual(StateDecay.decayed(.failed, silentFor: StateDecay.toSleeping * 2), .failed)
            expectEqual(StateDecay.decayed(.done, silentFor: StateDecay.toSleeping * 2), .done)
        }

        test("leaves a fresh state alone") {
            expectEqual(StateDecay.decayed(.working, silentFor: StateDecay.toIdle - 1), .working)
        }

        test("ranks attention above activity") {
            expect(AgentState.needsInput.priority > AgentState.working.priority,
                   "a question must outrank ordinary work")
            expect(AgentState.failed.priority > AgentState.needsInput.priority,
                   "an error must outrank a question")
            expect(AgentState.sleeping.priority < AgentState.idle.priority,
                   "sleeping must be the quietest state")
        }

        test("counts only producing states as busy") {
            expect(AgentState.working.isBusy && AgentState.delegating.isBusy, "work and delegation drum")
            expect(!AgentState.thinking.isBusy && !AgentState.idle.isBusy, "waiting does not drum")
        }

        test("marks exactly the states that wait to be seen") {
            let waiting = AgentState.allCases.filter(\.persistsUntilSeen)

            expectEqual(Set(waiting), Set([.needsInput, .done, .failed]))
        }
    }
}

@MainActor
func runGitContextTests() {
    suite("Workspace naming") {
        // Conductor names a workspace folder independently of its branch, so the
        // folder name alone can be meaningless ("cebu-v2").
        test("prefers the branch over the folder name") {
            let info = WorkspaceInfo(directory: "cebu-v2", project: "DinoTokenBar",
                                     branch: "lucas/bongo-token-bar")

            expectEqual(info.shortLabel, "bongo-token-bar", "the prefix does not fit under a cat")
            expectEqual(info.fullLabel, "DinoTokenBar · lucas/bongo-token-bar")
        }

        test("falls back to the folder when git tells us nothing") {
            let info = WorkspaceInfo(directory: "cebu-v2", project: nil, branch: nil)

            expectEqual(info.shortLabel, "cebu-v2")
            expectEqual(info.fullLabel, "cebu-v2")
        }

        test("still names the project when the branch is unknown") {
            let info = WorkspaceInfo(directory: "cebu-v2", project: "DinoTokenBar", branch: nil)

            expectEqual(info.fullLabel, "DinoTokenBar · cebu-v2")
        }

        test("keeps an unprefixed branch whole") {
            let info = WorkspaceInfo(directory: "w", project: "p", branch: "main")

            expectEqual(info.shortLabel, "main")
        }

        // Conductor workspaces are git worktrees, where .git is a pointer file
        // rather than a directory — the normal case here, not an edge case.
        test("resolves branch and project for this very worktree") {
            let info = GitContext.resolve(FileManager.default.currentDirectoryPath)

            expect(info.branch != nil, "should read a branch from the worktree pointer, got \(String(describing: info.branch))")
            expect(info.project != nil, "should name the repository, got \(String(describing: info.project))")
        }

        test("degrades gracefully outside a repository") {
            let info = GitContext.resolve("/tmp")

            expectEqual(info.directory, "tmp")
            expectEqual(info.branch, nil)
        }
    }
}

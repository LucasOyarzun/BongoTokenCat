import Foundation

/// One Claude Code hook firing, forwarded verbatim by `bongo-hook.sh`.
///
/// Every field past `hookEventName` is optional on purpose: hooks carry different
/// payloads, and Claude Code adds fields over time. A missing field must degrade
/// the cat, never drop the event.
struct HookEvent: Codable, Sendable {
    let hookEventName: String
    let sessionId: String
    let cwd: String?
    let toolName: String?
    let agentType: String?
    let notificationType: String?
    let errorType: String?
    let messageText: String?
    let lastAssistantMessage: String?

    enum CodingKeys: String, CodingKey {
        case hookEventName = "hook_event_name"
        case sessionId = "session_id"
        case cwd
        case toolName = "tool_name"
        case agentType = "agent_type"
        case notificationType = "notification_type"
        case errorType = "error_type"
        case messageText = "message_text"
        case lastAssistantMessage = "last_assistant_message"
    }

    /// Assistant text carried by this event, whichever field it arrived in.
    var producedText: String? { messageText ?? lastAssistantMessage }

    var workspace: String {
        guard let cwd, !cwd.isEmpty else { return "unknown" }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }
}

/// Hook event name → agent state.
///
/// Deliberately a small table rather than logic spread across the app: adding a
/// Claude Code event means adding one line here.
enum EventMapping {
    static func state(for event: HookEvent) -> AgentState? {
        switch event.hookEventName {
        case "SessionStart":       return .idle
        case "SessionEnd":         return .sleeping
        case "UserPromptSubmit":   return .thinking
        case "PreToolUse":         return event.toolName == "Task" ? .delegating : .working
        case "PostToolUse":        return .working
        case "MessageDisplay":     return .working
        case "SubagentStart":      return .delegating
        case "SubagentStop":       return .working
        case "PostToolUseFailure": return .failed
        case "StopFailure":        return .failed
        case "Stop":               return .done
        case "Notification":       return notificationState(event.notificationType)
        case "Elicitation":        return .needsInput
        default:                   return nil
        }
    }

    /// Only some notifications actually want the user. `agent_completed` is a
    /// finished turn, not a question — treating it as needsInput would leave the
    /// cat begging for attention that nobody owes it.
    private static func notificationState(_ type: String?) -> AgentState {
        switch type {
        case "agent_completed": return .done
        default:                return .needsInput
        }
    }
}

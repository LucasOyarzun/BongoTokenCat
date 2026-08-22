import Foundation

/// What an agent is doing right now, as far as its hook events tell us.
///
/// Ordered by how much it wants your attention: when one cat has to stand for
/// several agents (single-cat mode), the highest priority wins.
enum AgentState: String, Codable, Sendable, CaseIterable {
    case sleeping
    case idle
    case thinking
    case working
    case delegating
    case done
    case needsInput
    case failed

    var priority: Int {
        switch self {
        case .sleeping:   return 0
        case .idle:       return 1
        case .thinking:   return 2
        case .working:    return 3
        case .delegating: return 4
        case .done:       return 5
        case .needsInput: return 6
        case .failed:     return 7
        }
    }

    /// States the cat drums in. Everything else holds its paws still.
    var isBusy: Bool { self == .working || self == .delegating }

    /// States that are waiting on the user rather than on the model — these keep
    /// their badge until the user acts instead of decaying on a timer.
    var awaitsUser: Bool { self == .needsInput }
}

/// Live view of one agent session.
struct Agent: Identifiable, Sendable {
    let id: String              // Claude Code session_id
    var state: AgentState
    /// Repository and branch behind `projectPath`. A Conductor workspace folder is
    /// named independently of its branch, so the branch is what actually identifies
    /// the work — and it keeps up when the folder is renamed.
    var workspaceInfo: WorkspaceInfo
    var projectPath: String
    var toolName: String?
    var lastEventAt: Date
    var lastMessage: String?

    /// Wall-clock instant the current drum burst should stop. Past = paws still.
    var drumsUntil: Date

    var isDrumming: Bool { drumsUntil > Date() }

    var label: String { workspaceInfo.shortLabel }
    var fullLabel: String { workspaceInfo.fullLabel }
}

/// How long a state survives without new events before it decays.
///
/// Agents go quiet for two very different reasons — the model is slow, or the
/// session is over — and only elapsed time tells them apart. Anything waiting on
/// the *user* is exempt: it must persist until the user actually acts.
enum StateDecay {
    static let toIdle: TimeInterval = 45
    static let toSleeping: TimeInterval = 15 * 60

    static func decayed(_ state: AgentState, silentFor elapsed: TimeInterval) -> AgentState {
        if state.awaitsUser { return state }
        if elapsed >= toSleeping { return .sleeping }
        if elapsed >= toIdle, state != .sleeping { return .idle }
        return state
    }
}

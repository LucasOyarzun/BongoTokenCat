import Foundation
import Observation

/// Live roster of agent sessions, keyed by Claude Code `session_id`.
///
/// Single source of truth for the overlay: hook events flow in, decayed states and
/// drum bursts flow out. Nothing here reaches for the network or the filesystem on
/// its own — `decay` takes the one existence check it needs as a parameter — which
/// is what keeps the state machine testable in isolation.
@MainActor
@Observable
final class AgentRegistry {
    private(set) var agents: [String: Agent] = [:]

    /// Sessions that ended and have been quiet long enough to stop showing.
    private static let removeAfter: TimeInterval = 30 * 60

    /// Agents worth drawing, in a stable order so cats do not swap places on screen.
    var visibleAgents: [Agent] {
        agents.values
            .sorted { ($0.label, $0.id) < ($1.label, $1.id) }
    }

    /// The single state standing for the whole fleet, for single-cat mode.
    var aggregateState: AgentState {
        visibleAgents.map(\.state).max { $0.priority < $1.priority } ?? .sleeping
    }

    /// Anything on screen that moves: a burst in flight, or a busy agent tapping
    /// between bursts. The overlay's animation timer runs exactly while this holds,
    /// so an idle fleet still costs nothing.
    var needsAnimation: Bool {
        visibleAgents.contains { $0.isDrumming || $0.state.isBusy }
    }

    func apply(_ event: HookEvent, now: Date = Date()) {
        guard let state = EventMapping.state(for: event) else { return }
        let burst = DrumEngine.burstDuration(for: event)
        let existing = agents[event.sessionId]

        let path = event.cwd ?? existing?.projectPath ?? ""
        agents[event.sessionId] = Agent(
            id: event.sessionId,
            state: state,
            workspaceInfo: path.isEmpty
                ? (existing?.workspaceInfo ?? WorkspaceInfo(directory: "unknown", project: nil, branch: nil))
                : GitContext.info(for: path, now: now),
            projectPath: path,
            toolName: event.toolName ?? existing?.toolName,
            lastEventAt: now,
            lastMessage: event.producedText ?? existing?.lastMessage,
            // Never cut a burst short: a fresh event extends the drumming, it does
            // not restart it, so back-to-back turns read as one continuous roll.
            drumsUntil: max(existing?.drumsUntil ?? .distantPast, now.addingTimeInterval(burst))
        )
    }

    /// Ages states that have gone quiet and drops sessions long dead.
    ///
    /// Called on a timer — decay is elapsed-time driven, not event driven, so
    /// nothing else would ever move an abandoned session off `working`.
    ///
    /// `workspaceExists` is injected rather than called directly so the state
    /// machine stays a pure function of its inputs under test. One `stat` per agent
    /// per tick is far cheaper than the git calls `apply` already makes.
    func decay(now: Date = Date(),
               workspaceExists: (String) -> Bool = FileManager.default.fileExists(atPath:)) {
        for (id, agent) in agents {
            // Archiving a Conductor workspace deletes its worktree directory, so a
            // vanished path means the session cannot still be alive. It goes now
            // rather than waiting out a decay it would never finish.
            if !agent.projectPath.isEmpty, !workspaceExists(agent.projectPath) {
                agents[id] = nil
                continue
            }
            let elapsed = now.timeIntervalSince(agent.lastEventAt)
            if elapsed >= Self.removeAfter, agent.state == .sleeping {
                agents[id] = nil
                continue
            }
            let aged = StateDecay.decayed(agent.state, silentFor: elapsed)
            guard aged != agent.state else { continue }
            agents[id]?.state = aged
        }
    }

    /// Clears a "waiting for you" flag once the user has clearly moved on.
    func acknowledge(_ sessionID: String) {
        guard agents[sessionID]?.state.awaitsUser == true else { return }
        agents[sessionID]?.state = .idle
    }

    func removeAll() { agents.removeAll() }
}

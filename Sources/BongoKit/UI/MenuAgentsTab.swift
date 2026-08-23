import SwiftUI

/// What is running right now, and what the tokens it burned have bought you.
struct MenuAgentsTab: View {
    let model: AppModel
    let registry: AgentRegistry

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !model.hooksInstalled { setupCard }
            usageSection
            Divider()
            agentsSection
        }
    }

    // MARK: - Setup

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Hooks not installed", systemImage: "bolt.horizontal.circle")
                .font(.headline)
            Text("BongoTokenCat needs to register hooks in ~/.claude/settings.json to see what your agents are doing. Your existing hooks are kept — a backup is written first.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Install hooks") { model.installHooks() }
                .buttonStyle(.borderedProminent)
            if let error = model.lastInstallError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
    }

    // MARK: - Usage

    private var usageSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Tokens").font(.headline)
                Spacer()
                if model.isScanning { ProgressView().controlSize(.small) }
            }
            HStack(alignment: .top, spacing: 0) {
                stat("Today", TokenFormatter.compact(model.totals.today))
                Spacer(minLength: 8)
                stat("All time", TokenFormatter.compact(model.totals.lifetime))
                Spacer(minLength: 8)
                stat("To spend", TokenFormatter.compact(model.balance))
            }
            if let next = model.nextInstrument {
                VStack(alignment: .leading, spacing: 3) {
                    ProgressView(value: model.progressTowardNextInstrument())
                    Text("Next: \(next.name) at \(TokenFormatter.compact(next.tokensRequired))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.system(.title3, design: .rounded).weight(.semibold))
        }
    }

    // MARK: - Agents

    private var agentsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Agents").font(.headline)
            let agents = registry.visibleAgents
            if agents.isEmpty {
                Text("Nothing running. Start a Claude Code session and a cat appears.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(agents) { agent in
                    HStack(spacing: 8) {
                        Circle().fill(color(for: agent.state)).frame(width: 8, height: 8)
                        Text(agent.fullLabel).font(.callout).lineLimit(1).truncationMode(.head)
                        Spacer()
                        Text(description(of: agent))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private func description(of agent: Agent) -> String {
        switch agent.state {
        case .working:    return agent.toolName.map { "working · \($0)" } ?? "working"
        case .delegating: return "subagents"
        case .thinking:   return "thinking"
        case .needsInput: return "waiting for you"
        case .failed:     return "error"
        case .done:       return "done"
        case .idle:       return "idle"
        case .sleeping:   return "asleep"
        }
    }

    private func color(for state: AgentState) -> Color {
        switch state {
        case .working, .delegating: return .green
        case .thinking:             return .blue
        case .needsInput:           return .orange
        case .failed:               return .red
        case .done:                 return .teal
        case .idle:                 return .gray
        case .sleeping:             return .gray.opacity(0.4)
        }
    }
}

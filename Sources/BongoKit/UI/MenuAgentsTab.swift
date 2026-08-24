import SwiftUI

/// What is running right now, and what the tokens it burned have bought you.
struct MenuAgentsTab: View {
    let model: AppModel
    let registry: AgentRegistry

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !model.hooksInstalled { setupCard }
            usageSection
            limitsSection
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

    // MARK: - Limits

    /// Sits under the token counters because it answers the question they raise.
    /// They say what has been spent; this says how much room is left before the
    /// wall — a different number from a different source, and the one you actually
    /// plan a day around.
    @ViewBuilder
    private var limitsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Limits").font(.headline)
                Spacer()
                if model.isRefreshingLimits {
                    ProgressView().controlSize(.small)
                } else if model.showsUsageLimits {
                    Button {
                        Task { await model.refreshLimits(userInitiated: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh limits")
                }
            }
            limitsBody
        }
    }

    @ViewBuilder
    private var limitsBody: some View {
        switch model.limitsState {
        case .off:
            enableLimitsCard
        case .waiting:
            Text("Checking your quota…").font(.caption).foregroundStyle(.secondary)
        case .ready(let limits) where limits.isEmpty:
            Text("Your account reports no usage limits.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .ready(let limits):
            ForEach(limits.windows) { limitRow($0) }
        case .needsAuthorization:
            authorizationCard
        case .unavailable(let reason):
            Text(reason).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var enableLimitsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("See how much of your session and weekly quota is left. This asks Anthropic for your own account's limits — the only thing in this app that uses the network.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Show limits") { model.setUsageLimits(enabled: true) }
                .buttonStyle(.bordered)
        }
    }

    private var authorizationCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("macOS needs your permission to read the Claude Code credential from the Keychain. Choose Always Allow and this stops asking.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Allow access") {
                Task { await model.refreshLimits(userInitiated: true) }
            }
            .buttonStyle(.bordered)
        }
    }

    private func limitRow(_ window: LimitWindow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(window.name).font(.callout).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 4)
                Text(percentText(window))
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(color(forUsed: window.usedPercent))
                if let reset = window.resetsAt {
                    Text(reset, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            // The bar always fills with what has been used, whichever way the number
            // beside it is phrased: its job is "how close to the wall", and so is the
            // colour. A bar that emptied as the text counted down would say the same
            // thing twice and leave the colour thresholds meaningless.
            ProgressView(value: min(window.usedPercent, 100), total: 100)
                .tint(color(forUsed: window.usedPercent))
                .controlSize(.small)
        }
    }

    private func percentText(_ window: LimitWindow) -> String {
        model.limitsShowRemaining
            ? "\(TokenFormatter.percent(window.remainingPercent)) left"
            : "\(TokenFormatter.percent(window.usedPercent)) used"
    }

    private func color(forUsed used: Double) -> Color {
        if used >= 90 { return .red }
        if used >= 70 { return .orange }
        return .primary
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

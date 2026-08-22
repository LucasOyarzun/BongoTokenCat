import SwiftUI

/// The menu bar popover: setup, usage, skins, and what every agent is doing.
struct MenuContentView: View {
    @Bindable var model: AppModel
    @Bindable var settings: Settings
    let registry: AgentRegistry
    let onSettingsChanged: () -> Void
    let onResetPosition: () -> Void
    let onQuit: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !model.hooksInstalled { setupCard }
                usageSection
                Divider()
                agentsSection
                Divider()
                appearanceSection
                Divider()
                skinsSection
                footer
            }
            .padding(14)
        }
        .frame(width: 320)
    }

    // MARK: - Setup

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Hooks not installed", systemImage: "bolt.horizontal.circle")
                .font(.headline)
            Text("BongoTokenBar needs to register hooks in ~/.claude/settings.json to see what your agents are doing. Your existing hooks are kept — a backup is written first.")
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
            HStack {
                stat("Today", TokenFormatter.compact(model.totals.today))
                Spacer()
                stat("All time", TokenFormatter.compact(model.totals.lifetime))
            }
            if let next = model.nextSkin {
                VStack(alignment: .leading, spacing: 3) {
                    ProgressView(value: model.progressTowardNextSkin())
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

    // MARK: - Appearance

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cats").font(.headline)

            Picker("Show", selection: $settings.catMode) {
                ForEach(CatMode.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.radioGroup)
            .onChange(of: settings.catMode) { _, _ in onSettingsChanged() }

            Toggle("Show on desktop", isOn: $settings.showsOverlay)
                .onChange(of: settings.showsOverlay) { _, _ in onSettingsChanged() }

            Toggle("Label with workspace", isOn: $settings.showsWorkspaceLabels)
                .onChange(of: settings.showsWorkspaceLabels) { _, _ in onSettingsChanged() }

            Picker("Corner", selection: $settings.anchor) {
                ForEach(OverlayAnchor.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .onChange(of: settings.anchor) { _, _ in onSettingsChanged() }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Size").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(settings.catWidth)) pt").font(.caption2).foregroundStyle(.secondary)
                }
                Slider(value: $settings.catWidth,
                       in: Settings.minimumCatWidth...Settings.maximumCatWidth)
                    .onChange(of: settings.catWidth) { _, _ in onSettingsChanged() }
            }

            HStack {
                Text("Drag a cat to move it anywhere.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reset", action: onResetPosition)
                    .buttonStyle(.link)
                    .font(.caption2)
            }
        }
    }

    // MARK: - Skins

    private var skinsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Skins").font(.headline)
            ForEach(SkinCatalog.all) { skin in
                skinRow(skin)
            }
        }
    }

    private func skinRow(_ skin: Skin) -> some View {
        let unlocked = model.isUnlocked(skin)
        let selected = settings.skinID == skin.id
        return Button {
            guard unlocked else { return }
            settings.skinID = skin.id
            onSettingsChanged()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: unlocked ? (selected ? "largecircle.fill.circle" : "circle") : "lock.fill")
                    .foregroundStyle(unlocked ? Color.accentColor : .secondary)
                Text(skin.name)
                Spacer()
                if !unlocked {
                    Text(TokenFormatter.compact(skin.tokensRequired))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if model.hooksInstalled {
                Button("Remove hooks") { model.uninstallHooks() }
                    .buttonStyle(.link)
                    .font(.caption)
            }
            Spacer()
            Button("Quit", action: onQuit)
                .buttonStyle(.link)
                .font(.caption)
        }
    }
}

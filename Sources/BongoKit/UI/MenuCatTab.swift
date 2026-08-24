import SwiftUI

/// How the cats look and where they sit, plus the instrument track they earn.
struct MenuCatTab: View {
    let model: AppModel
    @Bindable var settings: Settings
    let onSettingsChanged: () -> Void
    let onResetPosition: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            appearanceSection
            Divider()
            limitsSection
            Divider()
            instrumentsSection
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

    // MARK: - Limits

    /// The section itself lives in the Agents tab; its preferences live here with
    /// the rest of them.
    private var limitsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Limits").font(.headline)

            // Not a plain binding onto `settings`: switching this on is what permits
            // the app's only network call, so it goes through the model that makes it.
            Toggle("Show usage limits", isOn: Binding(
                get: { model.showsUsageLimits },
                set: { model.setUsageLimits(enabled: $0) }))

            Picker("Show", selection: Binding(
                get: { model.limitsShowRemaining },
                set: { model.setLimitsShowRemaining($0) })) {
                Text("Remaining").tag(true)
                Text("Used").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(!model.showsUsageLimits)

            Text("Asks Anthropic for your account's own quota, using the credential Claude Code already stores on this Mac.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Instruments

    private var instrumentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Instruments").font(.headline)
            Text("Earned by working. Nothing to spend.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            ForEach(InstrumentCatalog.all) { instrument in
                instrumentRow(instrument)
            }
        }
    }

    private func instrumentRow(_ instrument: Instrument) -> some View {
        let unlocked = model.isUnlocked(instrument)
        let selected = settings.instrumentID == instrument.id
        return Button {
            guard unlocked else { return }
            settings.instrumentID = instrument.id
            onSettingsChanged()
        } label: {
            HStack(spacing: 10) {
                InstrumentPreview(instrument: instrument, coat: settings.coat, isUnlocked: unlocked)
                VStack(alignment: .leading, spacing: 1) {
                    Text(instrument.name).font(.callout)
                    if !unlocked {
                        Text("Unlocks at \(TokenFormatter.compact(instrument.tokensRequired))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: unlocked ? (selected ? "largecircle.fill.circle" : "circle") : "lock.fill")
                    .foregroundStyle(unlocked ? Color.accentColor : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
        .accessibilityLabel(unlocked ? instrument.name
                                     : "\(instrument.name), locked until \(TokenFormatter.compact(instrument.tokensRequired)) tokens")
    }
}

/// A still of the cat mid-strike, so the row shows what the instrument actually
/// looks like rather than naming it and hoping.
private struct InstrumentPreview: View {
    let instrument: Instrument
    let coat: Coat
    let isUnlocked: Bool

    private static let width: Double = 76

    var body: some View {
        ZStack {
            sprite(CatSprites.bodyName)
            sprite(PawPose.down.spriteName(side: "left"))
            sprite(PawPose.down.spriteName(side: "right"))
        }
        .frame(width: Self.width, height: Self.width * CatSprites.aspectRatio)
        // Locked instruments go grey rather than hidden: the point of the ladder is
        // seeing what is coming.
        .colorMultiply(isUnlocked ? coat.bodyColor : .white)
        .saturation(isUnlocked ? 1 : 0)
        .opacity(isUnlocked ? 1 : 0.4)
    }

    @ViewBuilder
    private func sprite(_ name: String) -> some View {
        if let image = CatSprites.image(instrument: instrument.id, named: name) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        }
    }
}

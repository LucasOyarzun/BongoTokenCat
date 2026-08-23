import SwiftUI

/// How the cats look and where they sit, plus the skins they unlock.
struct MenuCatTab: View {
    let model: AppModel
    @Bindable var settings: Settings
    let onSettingsChanged: () -> Void
    let onResetPosition: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            appearanceSection
            Divider()
            skinsSection
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
}

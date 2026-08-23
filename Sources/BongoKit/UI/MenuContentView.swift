import SwiftUI

/// The three faces of the popover.
enum MenuTab: String, CaseIterable, Identifiable {
    case agents, cat, shop

    var id: String { rawValue }

    var label: String {
        switch self {
        case .agents: return "Agents"
        case .cat:    return "Cat"
        case .shop:   return "Shop"
        }
    }
}

/// The menu bar popover: a tab bar over what is running, how the cat looks, and
/// what there is to buy — with a footer that stays put whichever tab is open.
///
/// Tabs are a segmented control rather than a `TabView`: inside an `NSPopover` a
/// `TabView` brings its own chrome and its own ideas about sizing, both of which
/// fight a fixed-width panel. A segmented control is the macOS idiom here anyway.
struct MenuContentView: View {
    let model: AppModel
    @Bindable var settings: Settings
    let registry: AgentRegistry
    let onSettingsChanged: () -> Void
    let onResetPosition: () -> Void
    let onQuit: () -> Void

    @State private var tab: MenuTab = .agents

    /// Shared with the popover hosting this view, so the two cannot disagree about
    /// how much room the content needs.
    static let preferredSize = CGSize(width: 320, height: 550)

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $tab) {
                ForEach(MenuTab.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            // One fixed height rather than one per tab: AppKit sizes the popover
            // once, so letting each tab decide would leave the shortest with a pane
            // of dead space and clip the tallest.
            ScrollView {
                selectedTab.padding(14)
            }

            Divider()

            footer
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
        }
        .frame(width: Self.preferredSize.width, height: Self.preferredSize.height)
    }

    @ViewBuilder
    private var selectedTab: some View {
        switch tab {
        case .agents:
            MenuAgentsTab(model: model, registry: registry)
        case .cat:
            MenuCatTab(model: model,
                       settings: settings,
                       onSettingsChanged: onSettingsChanged,
                       onResetPosition: onResetPosition)
        case .shop:
            MenuShopTab(model: model, settings: settings, onSettingsChanged: onSettingsChanged)
        }
    }

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

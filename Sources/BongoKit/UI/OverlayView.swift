import SwiftUI

/// The contents of the desktop overlay: either one cat for the whole fleet, or one
/// per agent laid out in a grid.
struct OverlayView: View {
    let registry: AgentRegistry
    let settings: Settings
    let clock: DrumClock
    let columns: Int

    var body: some View {
        Group {
            switch settings.catMode {
            case .single:   singleCat
            case .perAgent: catGrid
            }
        }
        .padding(OverlayLayout.padding)
        .animation(.easeOut(duration: 0.18), value: registry.visibleAgents.map(\.id))
    }

    private var singleCat: some View {
        BongoCatView(
            state: registry.aggregateState,
            // The fleet drums until the last agent stops, so the single cat stands
            // for "anything at all is producing".
            drumsUntil: registry.visibleAgents.map(\.drumsUntil).max() ?? .distantPast,
            now: clock.now,
            instrument: settings.instrument,
            coat: settings.coat,
            width: settings.catWidth,
            label: settings.showsWorkspaceLabels ? fleetLabel : nil
        )
    }

    private var catGrid: some View {
        let agents = registry.visibleAgents
        let rows = agents.chunked(into: max(1, columns))
        return VStack(alignment: .leading, spacing: OverlayLayout.spacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: OverlayLayout.spacing) {
                    ForEach(row) { agent in
                        BongoCatView(
                            state: agent.state,
                            drumsUntil: agent.drumsUntil,
                            now: clock.now,
                            instrument: settings.instrument,
                            coat: settings.coat,
                            width: settings.catWidth,
                            label: settings.showsWorkspaceLabels ? agent.label : nil
                        )
                    }
                }
            }
        }
    }

    // MARK: - Derived values

    private var fleetLabel: String {
        let busy = registry.visibleAgents.filter { $0.state.isBusy }.count
        let total = registry.visibleAgents.count
        guard total > 0 else { return "no agents" }
        return busy > 0 ? "\(busy)/\(total) working" : "\(total) idle"
    }
}

extension Array {
    /// Splits into fixed-width rows for the grid.
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

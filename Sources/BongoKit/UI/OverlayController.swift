import AppKit
import SwiftUI

/// Owns the desktop overlay window.
///
/// One panel holds every cat rather than one panel per agent. With thirteen
/// workspaces open that is the difference between one window and thirteen, and it
/// makes layout a matter of arranging views instead of choreographing windows.
@MainActor
final class OverlayController {
    private var panel: NSPanel?
    private let registry: AgentRegistry
    private let settings: Settings
    private let clock = DrumClock()

    /// Identity of the currently mounted view tree. Rebuilding `NSHostingView` on
    /// every hook event would restart SwiftUI's state and stutter the animation, so
    /// it only happens when the shape of the overlay actually changes.
    private var mountedSignature: String?
    private weak var hostingView: OverlayHostingView<OverlayView>?

    init(registry: AgentRegistry, settings: Settings) {
        self.registry = registry
        self.settings = settings
    }

    /// Recomputes visibility, size and position. Cheap enough to call on every
    /// state change — AppKit no-ops a frame that did not move.
    func sync() {
        guard settings.showsOverlay, !catCount.isZero else {
            hide()
            return
        }
        let grid = currentGrid()
        let panel = panel ?? makePanel()
        self.panel = panel

        let signature = layoutSignature(columns: grid.columns)
        if signature != mountedSignature {
            let view = OverlayHostingView(
                rootView: OverlayView(registry: registry, settings: settings, clock: clock, columns: grid.columns)
            )
            view.onMoved = { [weak self] origin in self?.settings.moveOverlay(to: origin) }
            view.onTapped = { [weak self] index in self?.acknowledgeCat(at: index) }
            panel.contentView = view
            hostingView = view
            mountedSignature = signature
            // Only on a rebuild, so this stays quiet during a burst of hook events
            // while still recording every change to what is on screen.
            AppLog.write("overlay \(catCount) cats \(grid.columns)x\(grid.rows) size=\(grid.size)")
        }

        let frame = NSRect(origin: panelOrigin(for: grid.size), size: grid.size)
        panel.setFrame(frame, display: true)
        updateInteractiveRects(grid: grid)
        if !panel.isVisible { panel.orderFrontRegardless() }
        syncClock()
    }

    /// A dragged position wins over the anchor, clamped so a resize cannot push the
    /// overlay off screen and out of reach.
    private func panelOrigin(for size: CGSize) -> CGPoint {
        guard let dragged = settings.overlayOrigin else {
            return OverlayLayout.origin(for: size, in: screenFrame, anchor: settings.anchor)
        }
        return OverlayLayout.clamp(origin: dragged, size: size, to: screenFrame)
    }

    /// `cellFrames` is measured from the top; AppKit views measure from the bottom.
    private func updateInteractiveRects(grid: OverlayLayout.Grid) {
        let cells = OverlayLayout.cellFrames(count: catCount,
                                             columns: grid.columns,
                                             catWidth: settings.catWidth,
                                             showsLabel: settings.showsWorkspaceLabels)
        let flipped = cells.map {
            CGRect(x: $0.minX, y: grid.size.height - $0.maxY, width: $0.width, height: $0.height)
        }
        hostingView?.interactiveRects = flipped
        // An empty set here means the cats silently stop being draggable, which is
        // invisible until someone tries — so it is worth a line.
        if flipped.isEmpty, catCount > 0 { AppLog.write("warning: no drag targets for \(catCount) cats") }
    }

    /// Clicking a cat is the "I saw it" gesture. `done`, `failed` and `needsInput`
    /// hold their badge until it happens instead of fading on a timer, so without a
    /// way to dismiss them they would stay on screen forever.
    private func acknowledgeCat(at index: Int) {
        switch settings.catMode {
        case .single:
            registry.acknowledgeAll()
        case .perAgent:
            let agents = registry.visibleAgents
            guard agents.indices.contains(index) else { return }
            registry.acknowledge(agents[index].id)
        }
        sync()
    }

    func resetPosition() {
        settings.resetOverlayPosition()
        sync()
    }

    /// Starts the animation timer while anything on screen is moving — a burst, or
    /// a busy agent's tap between bursts — and stops it when nothing is. Called from
    /// `sync()` and from the app's decay tick, so a burst that simply runs out still
    /// shuts the timer down.
    private func syncClock() {
        switch (registry.needsAnimation, clock.isRunning) {
        case (true, false):  clock.start()
        case (false, true):  clock.stop()
        default:             break
        }
    }

    func tick() {
        syncClock()
    }

    func hide() {
        panel?.orderOut(nil)
        clock.stop()
    }

    func close() {
        panel?.close()
        panel = nil
    }

    // MARK: - Geometry

    private var catCount: Int {
        settings.catMode == .single ? min(1, registry.visibleAgents.count) : registry.visibleAgents.count
    }

    private var screenFrame: CGRect {
        NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }

    /// Everything that changes the *structure* of the view tree. Per-agent state and
    /// drum deadlines are deliberately absent: those flow through observation.
    private func layoutSignature(columns: Int) -> String {
        let ids = registry.visibleAgents.map(\.id).joined(separator: ",")
        return "\(settings.catMode.rawValue)|\(settings.skinID)|\(settings.catWidth)|\(settings.showsWorkspaceLabels)|\(columns)|\(ids)"
    }

    private func currentGrid() -> OverlayLayout.Grid {
        OverlayLayout.grid(
            count: catCount,
            catWidth: settings.catWidth,
            showsLabel: settings.showsWorkspaceLabels,
            screenWidth: screenFrame.width
        )
    }

    // MARK: - Panel

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        // Cats are draggable, so the panel has to see the mouse. Everything except
        // the cats themselves is made click-through by the content view's hitTest,
        // so the gaps still never steal a click.
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        return panel
    }
}

private extension Int {
    var isZero: Bool { self == 0 }
}

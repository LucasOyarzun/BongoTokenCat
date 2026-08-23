import AppKit
import SwiftUI

/// Entry point. The executable target is only a call to this, which keeps every
/// line of logic inside a library the tests can import.
public enum BongoTokenCat {
    @MainActor
    public static func run() -> Never {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)   // menu bar only, no Dock icon
        // Held for the process lifetime: NSApplication does not retain its delegate.
        retainedDelegate = delegate
        app.run()
        fatalError("NSApplication.run returned")
    }

    @MainActor private static var retainedDelegate: AppDelegate?
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let registry = AgentRegistry()
    private let settings = Settings()
    private let model = AppModel()

    private var overlay: OverlayController!
    private var server: HookServer?
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var decayTimer: Timer?
    private var usageTimer: Timer?

    /// State only ages, so it has to be re-evaluated on a clock rather than on
    /// events — an abandoned session emits nothing by definition.
    private static let decayInterval: TimeInterval = 5
    private static let usageInterval: TimeInterval = 5 * 60

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlay = OverlayController(registry: registry, settings: settings)
        startServer()
        buildStatusItem()
        startTimers()
        Task { await model.refreshTotals() }
        overlay.sync()
        AppLog.write("BongoTokenCat started")
    }

    func applicationWillTerminate(_ notification: Notification) {
        server?.stop()
        overlay?.close()
    }

    // MARK: - Wiring

    private func startServer() {
        let server = HookServer { [weak self] event in
            // Hook payloads arrive on a network queue; all state lives on the main
            // actor because the overlay reads it directly.
            Task { @MainActor in self?.receive(event) }
        }
        // Binding is asynchronous, so launch no longer waits on it. A hook that
        // fires in the gap finds no runtime.json and exits 0, which is the same
        // path it already takes when the app is not running.
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await server.start()
                self.server = server
            } catch {
                AppLog.write("hook server failed to start: \(error)")
                self.model.lastInstallError = "Could not open a local port for the hook listener."
            }
        }
    }

    private func receive(_ event: HookEvent) {
        registry.apply(event)
        overlay.sync()
        refreshStatusTitle()
    }

    private func startTimers() {
        decayTimer = Timer.scheduledTimer(withTimeInterval: Self.decayInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.registry.decay()
                self.overlay.sync()
                self.overlay.tick()
            }
        }
        usageTimer = Timer.scheduledTimer(withTimeInterval: Self.usageInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.model.refreshTotals()
                self?.refreshStatusTitle()
            }
        }
    }

    // MARK: - Menu bar

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.action = #selector(togglePopover)
        item.button?.target = self
        statusItem = item
        refreshStatusTitle()
    }

    private func refreshStatusTitle() {
        let working = registry.visibleAgents.filter { $0.state.isBusy }.count
        let waiting = registry.visibleAgents.filter { $0.state.awaitsUser }.count
        var parts = ["🐱"]
        if working > 0 { parts.append("\(working)") }
        if waiting > 0 { parts.append("⏳\(waiting)") }
        statusItem?.button?.title = parts.joined(separator: " ")
    }

    @objc private func togglePopover() {
        let popover = popover ?? makePopover()
        self.popover = popover
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        Task { await model.refreshTotals() }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func makePopover() -> NSPopover {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: MenuContentView.preferredSize.width,
                                     height: MenuContentView.preferredSize.height)
        popover.contentViewController = NSHostingController(
            rootView: MenuContentView(
                model: model,
                settings: settings,
                registry: registry,
                onSettingsChanged: { [weak self] in self?.overlay.sync() },
                onResetPosition: { [weak self] in self?.overlay.resetPosition() },
                onQuit: { NSApplication.shared.terminate(nil) }
            )
        )
        return popover
    }
}

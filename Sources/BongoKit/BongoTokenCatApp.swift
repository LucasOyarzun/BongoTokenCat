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
    private let settings: Settings
    private let model: AppModel

    private var overlay: OverlayController!
    private var server: HookServer?
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    /// Live only while the menu is open — see `startDismissMonitors`.
    private var dismissMonitors: [Any] = []
    private var decayTimer: Timer?
    private var usageTimer: Timer?
    private var limitsTimer: Timer?
    private var updateTimer: Timer?

    /// State only ages, so it has to be re-evaluated on a clock rather than on
    /// events — an abandoned session emits nothing by definition.
    private static let decayInterval: TimeInterval = 5
    private static let usageInterval: TimeInterval = 5 * 60
    /// Quota moves while you work, so it is worth a tighter clock than the transcript
    /// scan — but it is one HTTP call to someone else's undocumented endpoint, so not
    /// much tighter. Two minutes keeps the bars honest without leaning on it.
    private static let limitsInterval: TimeInterval = 2 * 60
    /// Once a day. A menu bar app runs for weeks between reboots, so checking only
    /// at launch would mean never on the machines that never restart — and releases
    /// land a few times a year, so anything tighter polls for a number that has not
    /// moved. Deliberately not wired to the popover as the limits are: opening the
    /// menu is a glance, and glances would spend the whole unauthenticated budget.
    private static let updateInterval: TimeInterval = 24 * 60 * 60
    private static let escapeKeyCode: UInt16 = 53

    /// Built here rather than from property defaults because the model spends from
    /// the same settings the menu writes to, and one of them has to exist first.
    override init() {
        let settings = Settings()
        self.settings = settings
        self.model = AppModel(settings: settings)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlay = OverlayController(registry: registry, settings: settings)
        startServer()
        buildStatusItem()
        startTimers()
        Task { await model.refreshTotals() }
        Task { await model.refreshLimits(userInitiated: false) }
        Task { await model.checkForUpdate() }
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
        limitsTimer = Timer.scheduledTimer(withTimeInterval: Self.limitsInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.model.refreshLimits(userInitiated: false) }
        }
        updateTimer = Timer.scheduledTimer(withTimeInterval: Self.updateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.model.checkForUpdate() }
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

    /// Opening the menu has to activate the app first.
    ///
    /// An accessory app is never the active app, so a popover shown from a status
    /// item takes key focus for an instant and then loses it again as AppKit settles
    /// activation back where it was. `.transient` reads that as a click outside, so
    /// the menu closed itself a second or two after opening with nobody having
    /// touched anything. Activating is also what makes the controls inside respond
    /// to their first click instead of swallowing it.
    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        let popover = popover ?? makePopover()
        self.popover = popover
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        Task { await model.refreshTotals() }
        // Deliberately not user-initiated: opening the menu is a glance, and a glance
        // should never be answered with a Keychain dialog. Only the section's own
        // buttons ask for that.
        Task { await model.refreshLimits(userInitiated: false) }
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        startDismissMonitors()
    }

    /// Closing is ours to decide (`.applicationDefined`), so these restore the one
    /// dismissal gesture the menu should have and no more: a click outside, or
    /// Escape. A *global* mouse monitor only sees events bound for other
    /// applications, which is exactly what "outside" means here — a click on the
    /// status item or on a cat still travels its own path and leaves the menu open.
    private func startDismissMonitors() {
        guard dismissMonitors.isEmpty else { return }
        let clickOutside = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.popover?.performClose(nil)
        }
        let escape = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == Self.escapeKeyCode else { return event }
            self?.popover?.performClose(nil)
            return nil
        }
        dismissMonitors = [clickOutside, escape].compactMap { $0 }
    }

    private func makePopover() -> NSPopover {
        let popover = NSPopover()
        popover.delegate = self
        // Not `.transient`: that hands closing to AppKit's idea of who is active,
        // which an accessory app loses the moment after it shows the popover.
        popover.behavior = .applicationDefined
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

/// Tying the monitors' lifetime to the popover's own close callback means no path
/// can leak one — dismissing by click, by Escape, or by pressing the status item
/// again all end up here.
extension AppDelegate: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        dismissMonitors.forEach(NSEvent.removeMonitor)
        dismissMonitors = []
    }
}

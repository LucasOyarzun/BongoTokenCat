import Foundation
import Observation

/// Everything the menu bar needs that is not per-agent state: the token scan, the
/// hook install, and the wallet the shop spends from.
@MainActor
@Observable
final class AppModel {
    var totals = TokenReader.Totals()
    var isScanning = false
    var hooksInstalled = HookInstaller.isInstalled
    var lastInstallError: String?

    /// Held so the wallet can answer in one place instead of every shop row doing
    /// its own arithmetic over totals and purchases.
    private let settings: Settings

    init(settings: Settings) {
        self.settings = settings
    }

    // MARK: - Instruments

    var nextInstrument: Instrument? { InstrumentCatalog.nextLocked(lifetimeTokens: totals.lifetime) }

    func isUnlocked(_ instrument: Instrument) -> Bool {
        InstrumentCatalog.isUnlocked(instrument, lifetimeTokens: totals.lifetime)
    }

    func progressTowardNextInstrument() -> Double {
        guard let next = nextInstrument else { return 1 }
        return InstrumentCatalog.progress(toward: next, lifetimeTokens: totals.lifetime)
    }

    // MARK: - Wallet

    var balance: Int {
        CoatShop.balance(lifetimeTokens: totals.lifetime, purchased: settings.purchasedCoatIDs)
    }

    var spent: Int { CoatShop.spent(purchased: settings.purchasedCoatIDs) }

    func owns(_ coat: Coat) -> Bool { CoatShop.owns(coat, purchased: settings.purchasedCoatIDs) }

    func canAfford(_ coat: Coat) -> Bool {
        CoatShop.canAfford(coat, lifetimeTokens: totals.lifetime, purchased: settings.purchasedCoatIDs)
    }

    /// Refuses rather than overdraws, so a stale menu cannot spend a balance that a
    /// rescan has already moved.
    func buy(_ coat: Coat) {
        guard canAfford(coat) else { return }
        settings.recordPurchase(of: coat)
        AppLog.write("bought coat \(coat.id) for \(coat.price), balance now \(balance)")
    }

    // MARK: - Scanning

    /// Scanning walks every transcript on disk, so it runs off the main actor and
    /// coalesces: a second request while one is in flight is dropped rather than
    /// queued, which keeps a fast refresh interval from stacking scans.
    func refreshTotals() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        let scanned = await Task.detached(priority: .utility) { TokenReader.read() }.value
        totals = scanned
    }

    // MARK: - Hooks

    func installHooks() {
        do {
            try HookInstaller.install()
            hooksInstalled = true
            lastInstallError = nil
        } catch {
            lastInstallError = error.localizedDescription
            AppLog.write("hook install failed: \(error)")
        }
    }

    func uninstallHooks() {
        do {
            try HookInstaller.uninstall()
            hooksInstalled = false
            lastInstallError = nil
        } catch {
            lastInstallError = error.localizedDescription
            AppLog.write("hook uninstall failed: \(error)")
        }
    }
}

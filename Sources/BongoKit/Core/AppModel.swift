import Foundation
import Observation

/// Everything the menu bar needs that is not per-agent state.
@MainActor
@Observable
final class AppModel {
    var totals = TokenReader.Totals()
    var isScanning = false
    var hooksInstalled = HookInstaller.isInstalled
    var lastInstallError: String?

    var unlockedSkins: [Skin] { SkinCatalog.unlocked(lifetimeTokens: totals.lifetime) }
    var nextSkin: Skin? { SkinCatalog.nextLocked(lifetimeTokens: totals.lifetime) }

    func isUnlocked(_ skin: Skin) -> Bool {
        SkinCatalog.isUnlocked(skin, lifetimeTokens: totals.lifetime)
    }

    func progressTowardNextSkin() -> Double {
        guard let next = nextSkin else { return 1 }
        return SkinCatalog.progress(toward: next, lifetimeTokens: totals.lifetime)
    }

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

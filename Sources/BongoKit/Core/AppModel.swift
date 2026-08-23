import Foundation
import Observation

/// What the limits section is able to show right now.
///
/// One value rather than a data field plus a scattering of flags: the states are
/// mutually exclusive, and every combination the UI has to render is one of these.
enum LimitsState: Sendable, Equatable {
    /// The user has not turned the section on.
    case off
    /// On, but nothing has come back yet.
    case waiting
    case ready(UsageLimits)
    /// The credential lives in the Keychain and macOS wants the user to say so.
    case needsAuthorization
    case unavailable(String)
}

/// Everything the menu bar needs that is not per-agent state: the token scan, the
/// hook install, the wallet the shop spends from, and the quota bars.
@MainActor
@Observable
final class AppModel {
    var totals = TokenReader.Totals()
    var isScanning = false
    var hooksInstalled = HookInstaller.isInstalled
    var lastInstallError: String?

    private(set) var limitsState: LimitsState = .off
    var isRefreshingLimits = false

    /// Held so the wallet can answer in one place instead of every shop row doing
    /// its own arithmetic over totals and purchases.
    private let settings: Settings
    private let limitsProvider: LimitsProviding

    /// Kept in memory only. It is never written anywhere, never logged, and dies
    /// with the process — the Keychain and Claude Code's own file remain the only
    /// places a token is stored on this machine.
    private var credential: ClaudeCredential?
    private var limitsBackoffUntil: Date?

    /// Set when the endpoint rejects a token that came from Claude Code's file. That
    /// file can hold a token well inside its stated lifetime that the server has
    /// already revoked, and retrying it forever would mean never reaching the live
    /// one in the Keychain.
    private var fileCredentialRejected = false

    init(settings: Settings, limitsProvider: LimitsProviding = AnthropicLimitsProvider()) {
        self.settings = settings
        self.limitsProvider = limitsProvider
        limitsState = settings.showsUsageLimits ? .waiting : .off
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

    // MARK: - Usage limits

    var showsUsageLimits: Bool { settings.showsUsageLimits }
    var limitsShowRemaining: Bool { settings.limitsShowRemaining }

    /// Turning the section on is what authorises the first network call, so it goes
    /// through here rather than through a binding straight onto `Settings` — the
    /// preference and the fetch it permits stay one action.
    func setUsageLimits(enabled: Bool) {
        settings.showsUsageLimits = enabled
        guard enabled else {
            limitsState = .off
            credential = nil
            return
        }
        limitsState = .waiting
        Task { await refreshLimits(userInitiated: true) }
    }

    func setLimitsShowRemaining(_ showRemaining: Bool) {
        settings.limitsShowRemaining = showRemaining
    }

    /// `userInitiated` is the difference between a click and a timer, and it decides
    /// two things: whether macOS may put a Keychain dialog on screen, and whether a
    /// backoff still applies. An unattended refresh is never allowed to interrupt.
    func refreshLimits(userInitiated: Bool) async {
        guard settings.showsUsageLimits, !isRefreshingLimits else { return }
        if !userInitiated, isWaitingOnUser { return }

        isRefreshingLimits = true
        defer { isRefreshingLimits = false }

        do {
            let credential = try await usableCredential(userInitiated: userInitiated)
            let windows = try await limitsProvider.windows(accessToken: credential.accessToken)
            limitsBackoffUntil = nil
            limitsState = .ready(UsageLimits(windows: windows, fetchedAt: Date()))
            // Percentages only — the log is the first thing anyone reads when a bar
            // looks wrong, and it must never be somewhere a token could end up.
            AppLog.write("limits: " + windows.map { "\($0.id)=\(Int($0.usedPercent))%" }.joined(separator: " "))
        } catch {
            absorb(error)
        }
    }

    /// True while the section is parked: either macOS is waiting for a click to
    /// release the credential, or the endpoint asked for room and the clock has not
    /// run out. Both mean an automatic refresh would achieve nothing.
    private var isWaitingOnUser: Bool {
        if limitsState == .needsAuthorization { return true }
        if let limitsBackoffUntil, limitsBackoffUntil > Date() { return true }
        return false
    }

    /// The file first, because reading it can never put a dialog on screen; the
    /// Keychain second, because it is the one that actually has a live token once
    /// Claude Code has rotated. The Keychain read blocks — sometimes for seconds on a
    /// locked keychain — so it runs off the main actor.
    private func usableCredential(userInitiated: Bool) async throws -> ClaudeCredential {
        if let credential, credential.isUsable { return credential }

        if !fileCredentialRejected, let fromFile = ClaudeCredentials.fromFile(), fromFile.isUsable {
            credential = fromFile
            return fromFile
        }

        let allowPrompt = userInitiated
        let fromKeychain = try await Task.detached(priority: .userInitiated) {
            try ClaudeCredentials.fromKeychain(allowPrompt: allowPrompt)
        }.value
        credential = fromKeychain
        return fromKeychain
    }

    /// Failures are absorbed rather than surfaced: this section is a bonus on top of
    /// an app whose job is animating cats, and nothing here is worth an alert. A
    /// failed refresh keeps the last good numbers on screen — a blip should not blank
    /// a section the user is looking at.
    private func absorb(_ error: Error) {
        if case LimitsFetchError.rateLimited(let retryAfter) = error {
            limitsBackoffUntil = Date().addingTimeInterval(retryAfter ?? Self.defaultBackoff)
        }
        if case LimitsFetchError.unauthorized = error {
            // Retiring the source too, not just the value: re-reading the same file
            // would hand back the same dead token on the next tick.
            if credential?.source == .file { fileCredentialRejected = true }
            credential = nil
        }
        AppLog.write("limits refresh failed: \(error)")

        if case CredentialError.needsAuthorization = error {
            limitsState = .needsAuthorization
            return
        }
        if case .ready = limitsState { return }
        limitsState = .unavailable((error as? LocalizedError)?.errorDescription ?? "Limits unavailable.")
    }

    private static let defaultBackoff: TimeInterval = 5 * 60

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

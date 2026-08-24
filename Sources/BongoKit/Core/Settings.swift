import Foundation
import Observation

/// How many cats to show.
enum CatMode: String, Codable, Sendable, CaseIterable {
    /// One cat standing for everything you have running.
    case single
    /// One cat per agent session, labelled by workspace.
    case perAgent

    var label: String {
        switch self {
        case .single:   return "One cat"
        case .perAgent: return "One cat per agent"
        }
    }
}

@MainActor
@Observable
final class Settings {
    private let defaults = UserDefaults.standard

    var catMode: CatMode {
        didSet { defaults.set(catMode.rawValue, forKey: Keys.catMode) }
    }
    var instrumentID: String {
        didSet { defaults.set(instrumentID, forKey: Keys.instrumentID) }
    }
    var coatID: String {
        didSet { defaults.set(coatID, forKey: Keys.coatID) }
    }
    var catWidth: Double {
        didSet { defaults.set(catWidth, forKey: Keys.catWidth) }
    }
    var showsOverlay: Bool {
        didSet { defaults.set(showsOverlay, forKey: Keys.showsOverlay) }
    }
    var showsWorkspaceLabels: Bool {
        didSet { defaults.set(showsWorkspaceLabels, forKey: Keys.showsWorkspaceLabels) }
    }

    /// Off until asked for. Every other number in the app is read from files already
    /// on the disk; this one is the only thing that opens a network connection, so
    /// it is the user who decides that it may.
    var showsUsageLimits: Bool {
        didSet { defaults.set(showsUsageLimits, forKey: Keys.showsUsageLimits) }
    }

    /// "83% left" rather than "17% used". Both are the same number and people read
    /// quota in opposite directions, so it is a preference rather than a choice made
    /// once on everybody's behalf.
    var limitsShowRemaining: Bool {
        didSet { defaults.set(limitsShowRemaining, forKey: Keys.limitsShowRemaining) }
    }

    /// On by default, unlike the limits section. Both open a network connection, but
    /// this one is anonymous, carries no credential, and asks a public API for a
    /// number that is already public — and an app that quietly goes stale is a worse
    /// default than one that mentions a release exists.
    var checksForUpdates: Bool {
        didSet { defaults.set(checksForUpdates, forKey: Keys.checksForUpdates) }
    }

    /// Coats bought from the shop. Only ever added to — a coat you paid for stays
    /// yours, and the balance it cost comes back as the lifetime count grows.
    private(set) var purchasedCoatIDs: Set<String> {
        didSet { defaults.set(Array(purchasedCoatIDs), forKey: Keys.purchasedCoatIDs) }
    }

    /// Where the user dragged the cats to. `nil` means "keep the default corner",
    /// which is also what Reset position restores.
    private(set) var overlayOrigin: CGPoint?

    private enum Keys {
        static let catMode = "catMode"
        static let instrumentID = "instrumentID"
        static let coatID = "coatID"
        static let purchasedCoatIDs = "purchasedCoatIDs"
        static let catWidth = "catWidth"
        static let showsOverlay = "showsOverlay"
        static let showsWorkspaceLabels = "showsWorkspaceLabels"
        static let showsUsageLimits = "showsUsageLimits"
        static let limitsShowRemaining = "limitsShowRemaining"
        static let checksForUpdates = "checksForUpdates"
        static let hasCustomPosition = "hasCustomPosition"
        static let originX = "overlayOriginX"
        static let originY = "overlayOriginY"
    }

    /// 44pt still reads as a cat at a glance; below that the paws stop being
    /// legible, which is the whole point of the thing.
    static let minimumCatWidth: Double = 44
    static let maximumCatWidth: Double = 320
    static let defaultCatWidth: Double = 96

    init() {
        catMode = CatMode(rawValue: defaults.string(forKey: Keys.catMode) ?? "") ?? .perAgent
        instrumentID = defaults.string(forKey: Keys.instrumentID) ?? InstrumentCatalog.defaultInstrument.id
        coatID = defaults.string(forKey: Keys.coatID) ?? CoatShop.defaultCoat.id
        purchasedCoatIDs = Set(defaults.stringArray(forKey: Keys.purchasedCoatIDs) ?? [])
        catWidth = defaults.object(forKey: Keys.catWidth) as? Double ?? Self.defaultCatWidth
        showsOverlay = defaults.object(forKey: Keys.showsOverlay) as? Bool ?? true
        showsWorkspaceLabels = defaults.object(forKey: Keys.showsWorkspaceLabels) as? Bool ?? true
        showsUsageLimits = defaults.object(forKey: Keys.showsUsageLimits) as? Bool ?? false
        limitsShowRemaining = defaults.object(forKey: Keys.limitsShowRemaining) as? Bool ?? true
        checksForUpdates = defaults.object(forKey: Keys.checksForUpdates) as? Bool ?? true
        if defaults.bool(forKey: Keys.hasCustomPosition) {
            overlayOrigin = CGPoint(x: defaults.double(forKey: Keys.originX),
                                    y: defaults.double(forKey: Keys.originY))
        }
    }

    func recordPurchase(of coat: Coat) {
        purchasedCoatIDs.insert(coat.id)
    }

    func moveOverlay(to origin: CGPoint) {
        overlayOrigin = origin
        defaults.set(true, forKey: Keys.hasCustomPosition)
        defaults.set(origin.x, forKey: Keys.originX)
        defaults.set(origin.y, forKey: Keys.originY)
    }

    func resetOverlayPosition() {
        overlayOrigin = nil
        defaults.set(false, forKey: Keys.hasCustomPosition)
    }

    var instrument: Instrument { InstrumentCatalog.instrument(id: instrumentID) }
    var coat: Coat { CoatShop.coat(id: coatID) }
}

import Foundation

/// What the cat plays: a folder of five sprites — the body it sits at, and the
/// four paw poses that go with it.
///
/// Instruments are the free reward track. They cost nothing to select; passing the
/// threshold is the whole transaction, so a session spent working always leaves you
/// closer to the next one.
struct Instrument: Identifiable, Sendable, Equatable {
    /// Also the sprite folder name under `Resources/images`.
    let id: String
    let name: String
    let tokensRequired: Int

    var isFree: Bool { tokensRequired == 0 }
}

/// The unlock ladder.
///
/// Thresholds are calibrated against real usage rather than round numbers: a heavy
/// multi-workspace week lands around 1B tokens, a month around 5B. That puts the
/// first two unlocks within reach of anyone already using the app daily, and leaves
/// the genuine long haul to the shop, where colours are bought rather than earned.
///
/// All four come from bongocat-osu, which draws its game modes on one canvas with
/// the same cat body — so a mode is already an instrument, with paw poses the
/// artist registered against it. Its two remaining modes are missing here because
/// they draw the second arm as a curve chasing the cursor rather than as a sprite.
enum InstrumentCatalog {
    static let all: [Instrument] = [
        Instrument(id: "bongos",    name: "Bongos", tokensRequired: 0),
        Instrument(id: "keyboard4", name: "4-Key",  tokensRequired: 1_000_000_000),
        Instrument(id: "keyboard7", name: "7-Key",  tokensRequired: 5_000_000_000),
        Instrument(id: "arcade",    name: "Arcade", tokensRequired: 15_000_000_000),
    ]

    static let defaultInstrument = all[0]

    static func instrument(id: String) -> Instrument {
        all.first { $0.id == id } ?? defaultInstrument
    }

    static func isUnlocked(_ instrument: Instrument, lifetimeTokens: Int) -> Bool {
        lifetimeTokens >= instrument.tokensRequired
    }

    static func unlocked(lifetimeTokens: Int) -> [Instrument] {
        all.filter { isUnlocked($0, lifetimeTokens: lifetimeTokens) }
    }

    /// The cheapest instrument still out of reach — what the menu shows as "next up".
    static func nextLocked(lifetimeTokens: Int) -> Instrument? {
        all.first { !isUnlocked($0, lifetimeTokens: lifetimeTokens) }
    }

    /// Progress toward `instrument` measured from the previous threshold, so each
    /// unlock starts an empty bar instead of one already three quarters full.
    static func progress(toward instrument: Instrument, lifetimeTokens: Int) -> Double {
        guard instrument.tokensRequired > 0 else { return 1 }
        let floorTokens = all.last { $0.tokensRequired < instrument.tokensRequired }?.tokensRequired ?? 0
        let span = Double(instrument.tokensRequired - floorTokens)
        guard span > 0 else { return 1 }
        let gained = Double(lifetimeTokens - floorTokens)
        return min(max(gained / span, 0), 1)
    }
}

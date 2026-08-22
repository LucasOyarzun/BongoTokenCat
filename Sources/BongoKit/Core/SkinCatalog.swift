import SwiftUI

/// An unlockable coat colour for the cat.
///
/// Colour rather than props, because the sprites are a filled white body: a colour
/// multiply recolours the whole cat for free, so the entire reward track costs no
/// new artwork. (The earlier line-art sprites could not do this — multiplying a
/// black stroke leaves it black.)
struct Skin: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    /// `nil` leaves the artwork as drawn — a plain white cat.
    let hex: String?
    let tokensRequired: Int

    var bodyColor: Color { hex.map { Color(hex: $0) } ?? .white }

    var isFree: Bool { tokensRequired == 0 }
}

/// The unlock track.
///
/// Thresholds are calibrated against real usage rather than round numbers: a heavy
/// multi-workspace week lands around 1B tokens, a month around 5B. That puts the
/// first two unlocks within reach of anyone already using the app daily and keeps
/// the last one a genuine long-haul goal.
///
/// Colours stay pale on purpose. `colorMultiply` darkens whatever it touches, so a
/// saturated value turns a white cat muddy instead of tinting it.
enum SkinCatalog {
    static let all: [Skin] = [
        Skin(id: "white",  name: "Classic", hex: nil,       tokensRequired: 0),
        Skin(id: "peach",  name: "Peach",   hex: "#FFD9C0", tokensRequired: 1_000_000_000),
        Skin(id: "mint",   name: "Mint",    hex: "#C6EFDF", tokensRequired: 5_000_000_000),
        Skin(id: "sky",    name: "Sky",     hex: "#CBE3FA", tokensRequired: 15_000_000_000),
        Skin(id: "lilac",  name: "Lilac",   hex: "#DCD1F5", tokensRequired: 40_000_000_000),
        Skin(id: "gold",   name: "Gold",    hex: "#F5DFA0", tokensRequired: 100_000_000_000),
    ]

    static let defaultSkin = all[0]

    static func skin(id: String) -> Skin { all.first { $0.id == id } ?? defaultSkin }

    static func isUnlocked(_ skin: Skin, lifetimeTokens: Int) -> Bool {
        lifetimeTokens >= skin.tokensRequired
    }

    static func unlocked(lifetimeTokens: Int) -> [Skin] {
        all.filter { isUnlocked($0, lifetimeTokens: lifetimeTokens) }
    }

    /// The cheapest skin still out of reach — what the menu shows as "next up".
    static func nextLocked(lifetimeTokens: Int) -> Skin? {
        all.first { !isUnlocked($0, lifetimeTokens: lifetimeTokens) }
    }

    /// Progress toward `skin` measured from the previous threshold, so each unlock
    /// starts an empty bar instead of one already three quarters full.
    static func progress(toward skin: Skin, lifetimeTokens: Int) -> Double {
        guard skin.tokensRequired > 0 else { return 1 }
        let floorTokens = all.last { $0.tokensRequired < skin.tokensRequired }?.tokensRequired ?? 0
        let span = Double(skin.tokensRequired - floorTokens)
        guard span > 0 else { return 1 }
        let gained = Double(lifetimeTokens - floorTokens)
        return min(max(gained / span, 0), 1)
    }
}

extension Color {
    /// Parses `#RRGGBB`. Falls back to white, which is the identity for
    /// `colorMultiply` and therefore leaves the artwork as drawn.
    init(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = Int(digits, radix: 16) else { self = .white; return }
        self = Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

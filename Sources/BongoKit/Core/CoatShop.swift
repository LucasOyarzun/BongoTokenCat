import SwiftUI

/// A coat colour for the cat.
///
/// Colour rather than props, because the sprites are a filled white body: a colour
/// multiply recolours the whole cat for free, so the entire range costs no new
/// artwork. (The earlier line-art sprites could not do this — multiplying a black
/// stroke leaves it black.)
struct Coat: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    /// `nil` leaves the artwork as drawn — a plain white cat.
    let hex: String?
    let price: Int

    var bodyColor: Color { hex.map { Color(hex: $0) } ?? .white }

    /// Shipped with the app, so it is owned before anything has been spent.
    var isIncluded: Bool { price == 0 }
}

/// The colour shop.
///
/// Colours are bought, not earned. Instruments already reward simply having worked;
/// making the colours cost something turns the same counter into a decision — one
/// expensive coat or three cheap ones — which is worth more than a sixth threshold
/// crossed on autopilot.
///
/// The currency is the lifetime token count, which only ever grows, so a balance
/// spent down here recovers on its own. Owning everything costs 41B, well past the
/// top of the instrument ladder, which is what keeps a long-haul goal on the board.
///
/// Colours stay pale on purpose. `colorMultiply` darkens whatever it touches, so a
/// saturated value turns a white cat muddy instead of tinting it.
enum CoatShop {
    static let all: [Coat] = [
        Coat(id: "white",  name: "Classic", hex: nil,       price: 0),
        Coat(id: "peach",  name: "Peach",   hex: "#FFD9C0", price: 500_000_000),
        Coat(id: "mint",   name: "Mint",    hex: "#C6EFDF", price: 1_500_000_000),
        Coat(id: "sky",    name: "Sky",     hex: "#CBE3FA", price: 4_000_000_000),
        Coat(id: "lilac",  name: "Lilac",   hex: "#DCD1F5", price: 10_000_000_000),
        Coat(id: "gold",   name: "Gold",    hex: "#F5DFA0", price: 25_000_000_000),
    ]

    static let defaultCoat = all[0]

    static func coat(id: String) -> Coat { all.first { $0.id == id } ?? defaultCoat }

    static func owns(_ coat: Coat, purchased: Set<String>) -> Bool {
        coat.isIncluded || purchased.contains(coat.id)
    }

    /// Derived from what has been bought rather than kept as a running total, so
    /// the ledger cannot drift out of step with the coats it paid for.
    static func spent(purchased: Set<String>) -> Int {
        all.filter { purchased.contains($0.id) }.reduce(0) { $0 + $1.price }
    }

    /// Never negative: prices can be edited between releases, and an upgrade that
    /// makes an owned coat dearer should not read as debt.
    static func balance(lifetimeTokens: Int, purchased: Set<String>) -> Int {
        max(0, lifetimeTokens - spent(purchased: purchased))
    }

    static func canAfford(_ coat: Coat, lifetimeTokens: Int, purchased: Set<String>) -> Bool {
        guard !owns(coat, purchased: purchased) else { return false }
        return balance(lifetimeTokens: lifetimeTokens, purchased: purchased) >= coat.price
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

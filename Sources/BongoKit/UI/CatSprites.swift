import AppKit
import SwiftUI

/// The cat artwork: a filled white body plus one image per paw pose.
///
/// The first attempt used bongo.cat's own art, which is line work with a
/// transparent interior — it only reads as a white cat because that page has a
/// white background, and its outline is open so there is no region to fill. These
/// sprites come from bongocat-osu instead, where the body is already filled, and
/// were pre-processed once to strip the opaque white desk behind it.
///
/// Every layer shares one canvas, so they stack with no offsets: draw the body,
/// then each paw.
enum CatSprites {
    static let stageSize = CGSize(width: 607, height: 335)

    static var aspectRatio: CGFloat { stageSize.height / stageSize.width }

    /// Sprites are only ever loaded while rendering, so the cache lives on the main
    /// actor rather than behind a lock.
    @MainActor private static var cache: [String: NSImage] = [:]

    @MainActor
    static func image(named name: String) -> NSImage? {
        if let cached = cache[name] { return cached }
        guard let url = Bundle.module.url(forResource: "images/\(name)", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            AppLog.write("missing sprite: \(name).png")
            return nil
        }
        cache[name] = image
        return image
    }
}

/// One paw's pose. Each maps to its own image rather than to an offset into a
/// sprite sheet.
enum PawPose: String {
    case up, down

    func spriteName(side: String) -> String { "paw-\(side)-\(rawValue)" }
}

/// Which paws are where, for a given agent state and moment in time.
struct PawPosition: Equatable {
    var left: PawPose
    var right: PawPose

    static let bothUp = PawPosition(left: .up, right: .up)
    static let bothDown = PawPosition(left: .down, right: .down)

    /// Alternating strike pattern.
    ///
    /// The beat runs over a two-unit cycle: the left paw strikes in the first half
    /// of unit one, the right in the first half of unit two. The gap matters as
    /// much as the strike — paws pinned down read as a frozen cat, not a fast one.
    static func drumming(at time: TimeInterval, beatsPerSecond: Double) -> PawPosition {
        let cycle = (time * beatsPerSecond).truncatingRemainder(dividingBy: 2)
        let strikeWindow = 0.5
        return PawPosition(
            left: cycle < strikeWindow ? .down : .up,
            right: (cycle >= 1 && cycle < 1 + strikeWindow) ? .down : .up
        )
    }

    /// Resting pose for an agent that is not producing anything.
    static func resting(for state: AgentState) -> PawPosition {
        switch state {
        case .sleeping, .failed: return .bothDown          // slumped onto the drum
        case .needsInput:        return PawPosition(left: .up, right: .down)  // one paw raised
        default:                 return .bothUp            // poised, waiting on the model
        }
    }
}

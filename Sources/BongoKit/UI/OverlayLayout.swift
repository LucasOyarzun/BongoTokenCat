import Foundation

/// Grid geometry for the row of cats.
///
/// The window size and the SwiftUI layout have to agree exactly — a window even a
/// few points too small clips the cats, and one too large steals clicks from
/// whatever is behind it. Both read these numbers instead of each computing them.
enum OverlayLayout {
    static let spacing: Double = 12
    static let labelHeight: Double = 16
    static let padding: Double = 10

    /// Fraction of the screen the row may occupy before it wraps to a second row.
    private static let maxScreenFraction: Double = 0.9

    struct Grid: Equatable {
        let columns: Int
        let rows: Int
        let size: CGSize
    }

    static func cellSize(catWidth: Double, showsLabel: Bool) -> CGSize {
        let art = catWidth * CatSprites.aspectRatio
        return CGSize(width: catWidth, height: art + (showsLabel ? labelHeight : 0))
    }

    static func grid(count: Int, catWidth: Double, showsLabel: Bool, screenWidth: Double) -> Grid {
        let cell = cellSize(catWidth: catWidth, showsLabel: showsLabel)
        guard count > 0 else { return Grid(columns: 0, rows: 0, size: .zero) }

        let available = (screenWidth * maxScreenFraction) - (padding * 2)
        let fitting = max(1, Int((available + spacing) / (cell.width + spacing)))
        let columns = min(count, fitting)
        let rows = Int(ceil(Double(count) / Double(columns)))

        let width = (Double(columns) * cell.width) + (Double(columns - 1) * spacing) + (padding * 2)
        let height = (Double(rows) * cell.height) + (Double(rows - 1) * spacing) + (padding * 2)
        return Grid(columns: columns, rows: rows, size: CGSize(width: width, height: height))
    }

    /// Rect of each cat within the panel, top-left origin.
    ///
    /// Drives hit testing: the panel accepts the mouse so cats can be dragged, but
    /// only over a cat. The gaps stay click-through, so the overlay never steals a
    /// click meant for the window behind it.
    static func cellFrames(count: Int, columns: Int, catWidth: Double, showsLabel: Bool) -> [CGRect] {
        guard count > 0, columns > 0 else { return [] }
        let cell = cellSize(catWidth: catWidth, showsLabel: showsLabel)
        return (0..<count).map { index in
            let column = index % columns
            let row = index / columns
            return CGRect(
                x: padding + Double(column) * (cell.width + spacing),
                y: padding + Double(row) * (cell.height + spacing),
                width: cell.width,
                height: cell.height
            )
        }
    }

    /// Keeps a dragged overlay reachable after the cat count changes its size.
    static func clamp(origin: CGPoint, size: CGSize, to frame: CGRect) -> CGPoint {
        // A sliver has to stay on screen or the overlay becomes impossible to grab.
        let visible: Double = 24
        return CGPoint(
            x: min(max(origin.x, frame.minX - size.width + visible), frame.maxX - visible),
            y: min(max(origin.y, frame.minY - size.height + visible), frame.maxY - visible)
        )
    }

    /// Bottom-left origin for the panel, in screen coordinates.
    static func origin(for size: CGSize, in frame: CGRect, anchor: OverlayAnchor) -> CGPoint {
        let inset: Double = 16
        let x: Double
        let y: Double
        switch anchor {
        case .bottomLeading, .topLeading:
            x = frame.minX + inset
        case .bottomTrailing, .topTrailing:
            x = frame.maxX - size.width - inset
        }
        switch anchor {
        case .bottomLeading, .bottomTrailing:
            y = frame.minY + inset
        case .topLeading, .topTrailing:
            y = frame.maxY - size.height - inset
        }
        return CGPoint(x: x, y: y)
    }
}

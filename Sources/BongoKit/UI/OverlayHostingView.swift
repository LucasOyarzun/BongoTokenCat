import AppKit
import SwiftUI

/// The overlay's content view: click-through except over a cat, draggable, and
/// clickable — a click that does not travel acknowledges the cat under it.
///
/// A panel's `ignoresMouseEvents` is all-or-nothing, so making the cats draggable
/// would otherwise mean the whole panel rectangle — gaps included — swallowing
/// clicks meant for whatever is behind it. Overriding `hitTest` narrows that down
/// to the cats themselves.
/// Below this much travel a mouse-up is a click, not a drag. No real click is
/// perfectly still, and a one-pixel wobble must not read as a move. File scope
/// because a generic type cannot hold a static stored property.
private let dragThreshold: CGFloat = 3

final class OverlayHostingView<Content: View>: NSHostingView<Content> {

    /// Cat rects in this view's coordinate space. Set by the controller, which owns
    /// the layout maths.
    var interactiveRects: [CGRect] = []

    /// Called with the window's new bottom-left origin once a drag settles.
    var onMoved: ((CGPoint) -> Void)?

    /// Called with the index into `interactiveRects` of a cat that was clicked
    /// rather than dragged.
    var onTapped: ((Int) -> Void)?

    private var grabPoint: NSPoint?
    private var windowOrigin: NSPoint?
    private var pressedIndex: Int?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard interactiveRects.contains(where: { $0.contains(point) }) else { return nil }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        grabPoint = NSEvent.mouseLocation
        windowOrigin = window?.frame.origin
        let local = convert(event.locationInWindow, from: nil)
        pressedIndex = interactiveRects.firstIndex { $0.contains(local) }
    }

    /// Moves the window rather than the view: the cats keep their layout and the
    /// panel simply follows the cursor, which is what a desktop pet should do.
    override func mouseDragged(with event: NSEvent) {
        guard let grabPoint, let windowOrigin, let window else { return }
        let current = NSEvent.mouseLocation
        window.setFrameOrigin(NSPoint(x: windowOrigin.x + (current.x - grabPoint.x),
                                      y: windowOrigin.y + (current.y - grabPoint.y)))
    }

    override func mouseUp(with event: NSEvent) {
        defer { grabPoint = nil; windowOrigin = nil; pressedIndex = nil }
        guard let window, let grabPoint else { return }
        let travelled = NSEvent.mouseLocation.distance(to: grabPoint)
        // Reporting a click as a move would pin an overlay still following the
        // default corner to a position it never asked for, so the two paths stay
        // exclusive.
        guard travelled >= dragThreshold else {
            if let pressedIndex { onTapped?(pressedIndex) }
            return
        }
        onMoved?(window.frame.origin)
    }

    /// The panel never becomes key, so without this the first click after focus
    /// moves elsewhere would be swallowed just to activate it.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private extension NSPoint {
    func distance(to other: NSPoint) -> CGFloat { hypot(x - other.x, y - other.y) }
}

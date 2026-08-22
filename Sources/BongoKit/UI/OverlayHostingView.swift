import AppKit
import SwiftUI

/// The overlay's content view: click-through except over a cat, and draggable.
///
/// A panel's `ignoresMouseEvents` is all-or-nothing, so making the cats draggable
/// would otherwise mean the whole panel rectangle — gaps included — swallowing
/// clicks meant for whatever is behind it. Overriding `hitTest` narrows that down
/// to the cats themselves.
final class OverlayHostingView<Content: View>: NSHostingView<Content> {

    /// Cat rects in this view's coordinate space. Set by the controller, which owns
    /// the layout maths.
    var interactiveRects: [CGRect] = []

    /// Called with the window's new bottom-left origin once a drag settles.
    var onMoved: ((CGPoint) -> Void)?

    private var grabPoint: NSPoint?
    private var windowOrigin: NSPoint?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard interactiveRects.contains(where: { $0.contains(point) }) else { return nil }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        grabPoint = NSEvent.mouseLocation
        windowOrigin = window?.frame.origin
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
        defer { grabPoint = nil; windowOrigin = nil }
        guard let window, grabPoint != nil else { return }
        onMoved?(window.frame.origin)
    }

    /// The panel never becomes key, so without this the first click after focus
    /// moves elsewhere would be swallowed just to activate it.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

import AppKit

/// Base class for everything on the bar: hover/pressed drawing, click, middle-click, context menu and drag.
class BarItemView: NSView {
    weak var bar: BarContentView?

    var isHovered = false { didSet { if isHovered != oldValue { needsDisplay = true } } }
    var isPressed = false { didSet { if isPressed != oldValue { needsDisplay = true } } }
    /// Drawn with a persistent highlight (the focused window).
    var isActive = false { didSet { if isActive != oldValue { needsDisplay = true } } }

    private var trackingArea: NSTrackingArea?
    private var mouseDownX: CGFloat?
    private(set) var isDragging = false

    /// Text for the hover tip; `nil` shows none.
    var tipText: String? { nil }
    /// Whether this item can be dragged to reorder.
    var isDraggable: Bool { true }

    func primaryClick() {}
    func middleClick() {}
    func contextMenu() -> NSMenu? { bar?.barMenu() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        bar?.itemHoverChanged(self, hovering: true)
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        bar?.itemHoverChanged(self, hovering: false)
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        mouseDownX = event.locationInWindow.x
        bar?.itemHoverChanged(self, hovering: false)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownX, let bar else { return }
        let x = bar.convert(event.locationInWindow, from: nil).x
        if !isDragging {
            guard isDraggable, abs(event.locationInWindow.x - start) > 4 else { return }
            isDragging = true
            isPressed = false
            bar.beginDrag(self, atX: bar.convert(CGPoint(x: start, y: 0), from: nil).x)
        }
        bar.continueDrag(self, atX: x)
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            isPressed = false
            isDragging = false
            mouseDownX = nil
        }
        if isDragging {
            bar?.endDrag(self)
        } else if isPressed, bounds.contains(convert(event.locationInWindow, from: nil)) {
            primaryClick()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        bar?.itemHoverChanged(self, hovering: false)
        guard let menu = contextMenu() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func otherMouseUp(with event: NSEvent) {
        guard event.buttonNumber == 2, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        middleClick()
    }

    override func draw(_ dirtyRect: NSRect) {
        let alpha: CGFloat = isPressed ? 0.16 : isHovered ? 0.1 : isActive ? 0.12 : 0
        guard alpha > 0 else { return }
        NSColor.labelColor.withAlphaComponent(alpha).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill()
    }

    /// Draws an icon centred vertically at `x`.
    func drawIcon(_ image: NSImage?, x: CGFloat, size: CGFloat, alpha: CGFloat = 1) {
        guard let image else { return }
        let rect = CGRect(x: x, y: ((bounds.height - size) / 2).rounded(), width: size, height: size)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: alpha)
    }

    var iconSize: CGFloat { min(22, (bounds.height - 8).rounded()) }
}

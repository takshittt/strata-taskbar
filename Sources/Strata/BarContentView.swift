import AppKit

/// Draws a hairline along the top edge of the bar, re-resolving the color on appearance changes.
private final class SeparatorView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setFill()
        bounds.fill()
    }
}

/// The bar's root view: a blurred background with the bar items laid out on top.
final class BarContentView: NSView {
    private let background = NSVisualEffectView()
    private let separator = SeparatorView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.autoresizingMask = [.width, .height]
        addSubview(background)
        separator.autoresizingMask = [.width, .minYMargin]
        addSubview(separator)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { false }

    override func layout() {
        super.layout()
        background.frame = bounds
        separator.frame = CGRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1)
    }

    func applySettings(_ settings: Settings) {
        background.alphaValue = CGFloat(settings.opacity)
        needsLayout = true
    }
}

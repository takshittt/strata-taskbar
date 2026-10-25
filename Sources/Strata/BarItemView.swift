import AppKit

/// Base class for everything on the bar: hover/pressed drawing, click, middle-click, context menu and drag.
class BarItemView: NSView {
    weak var bar: BarContentView?

    var isHovered = false { didSet { if isHovered != oldValue { needsDisplay = true } } }
    var isPressed = false { didSet { if isPressed != oldValue { needsDisplay = true } } }
    /// Drawn with a persistent highlight (the focused window).
    var isActive = false { didSet { if isActive != oldValue { needsDisplay = true } } }
    /// Files are being dragged over this item and it will open (or pin) them.
    private var isDropTarget = false { didSet { if isDropTarget != oldValue { needsDisplay = true } } }

    private var trackingArea: NSTrackingArea?
    private var mouseDownX: CGFloat?
    private(set) var isDragging = false

    /// Text for the hover tip; `nil` shows none.
    var tipText: String? { nil }
    /// Whether this item can be dragged to reorder.
    var isDraggable: Bool { true }
    /// The app that opens files and folders dropped on this item, as on a Dock icon; `nil` refuses drops.
    var dropApp: URL? { nil }

    override init(frame: NSRect) {
        super.init(frame: frame)
        // Links, text and images too, so holding any drag over a window button brings the window forward.
        registerForDraggedTypes([.fileURL, .URL, .string, .tiff, .png])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func primaryClick() {}
    /// Shift-click: a plain click unless the item does something else.
    func shiftClick() { primaryClick() }
    func middleClick() {}
    /// Something has been dragged over the item and held there (Windows' spring-loading).
    func springLoaded() {}
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
            if event.modifierFlags.contains(.shift) { shiftClick() } else { primaryClick() }
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

    // MARK: Dropping files

    private static let springDelay: TimeInterval = 0.6
    private var springTimer: Timer?

    /// Dropped apps get pinned; other files open in `dropApp`.
    private func dropOperation(_ info: NSDraggingInfo) -> NSDragOperation {
        let urls = DroppedFiles.urls(info)
        guard !urls.isEmpty, DroppedFiles.appBundleIDs(urls) != nil || dropApp != nil else { return [] }
        return .copy
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        springTimer?.invalidate()
        springTimer = Timer.scheduledTimer(withTimeInterval: Self.springDelay, repeats: false) { [weak self] _ in
            // Only if the drag is still held over this item.
            guard let self, let window, NSEvent.pressedMouseButtons != 0,
                  bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil)) else { return }
            springLoaded()
        }
        let operation = dropOperation(sender)
        isDropTarget = !operation.isEmpty
        return operation
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        endDropHover()
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        endDropHover()
    }

    private func endDropHover() {
        springTimer?.invalidate()
        springTimer = nil
        isDropTarget = false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        endDropHover()
        return drop(DroppedFiles.urls(sender))
    }

    /// Pins dropped apps, or opens other files in `dropApp`. Returns whether the drop was taken.
    func drop(_ urls: [URL]) -> Bool {
        if let bundleIDs = DroppedFiles.appBundleIDs(urls) {
            bar?.pin(bundleIDs, at: self)
            return true
        }
        guard let app = dropApp, !urls.isEmpty else { return false }
        WindowActions.open(urls, with: app)
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        let alpha: CGFloat = isPressed || isDropTarget ? 0.16 : isHovered ? 0.1 : isActive ? 0.12 : 0
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

    var iconSize: CGFloat { min(CGFloat(Settings.shared.iconSize), (bounds.height - 8).rounded()) }
}

/// Reads files dragged onto the bar.
enum DroppedFiles {
    static func urls(_ info: NSDraggingInfo) -> [URL] {
        info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    /// The apps' bundle IDs when every dropped item is an app, otherwise `nil`.
    static func appBundleIDs(_ urls: [URL]) -> [String]? {
        guard !urls.isEmpty else { return nil }
        var bundleIDs: [String] = []
        for url in urls {
            guard url.pathExtension == "app", let bundleID = Bundle(url: url)?.bundleIdentifier else { return nil }
            bundleIDs.append(bundleID)
        }
        return bundleIDs
    }
}

/// A menu item that runs a closure. Never `copy()` one: the copy loses the closure.
final class MenuAction: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, enabled: Bool = true, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
        isEnabled = enabled
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func run() { handler() }
}

extension NSMenu {
    /// A menu that respects each item's `isEnabled` instead of validating against the responder chain.
    static func manual(_ title: String = "") -> NSMenu {
        let menu = NSMenu(title: title)
        menu.autoenablesItems = false
        return menu
    }

    /// A disabled item used as a section header.
    func addHeader(_ title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        addItem(item)
    }
}

/// Tooltip for bar items. `NSView.toolTip` is unreliable in a panel of an inactive app, so we draw our own.
/// Appears after a delay; moving straight to another item switches it instantly.
final class HoverTip {
    static let shared = HoverTip()

    private static let delay: TimeInterval = 0.6
    /// Moving to another item within this long of the tip hiding shows the next tip at once.
    private static let switchWindow: TimeInterval = 0.3
    private static let cornerRadius: CGFloat = 7
    private static let padding = CGSize(width: 12, height: 5)

    private let panel: NSPanel
    private let label = NSTextField(labelWithString: "")
    private weak var item: BarItemView?
    private var timer: Timer?
    private var lastHidden = Date.distantPast

    private init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true

        // Styled like the Dock's app-name labels: a rounded, translucent popover-material
        // plate with a hairline border and regular-size text, following light/dark mode.
        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = Self.cornerRadius
        background.layer?.cornerCurve = .continuous
        background.layer?.masksToBounds = true
        background.layer?.borderWidth = 0.5
        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        label.textColor = .labelColor
        label.lineBreakMode = .byClipping
        background.addSubview(label)
        panel.contentView = background
    }

    func hover(_ item: BarItemView) {
        timer?.invalidate()
        self.item = item
        if panel.isVisible || Date().timeIntervalSince(lastHidden) < Self.switchWindow {
            show()
        } else {
            timer = Timer.scheduledTimer(withTimeInterval: Self.delay, repeats: false) { [weak self] _ in self?.show() }
        }
    }

    /// The mouse left `item` (or pressed it): hide if it's the one showing.
    func leave(_ item: BarItemView) {
        guard self.item === item else { return }
        hide()
    }

    func hide() {
        timer?.invalidate()
        item = nil
        if panel.isVisible {
            panel.orderOut(nil)
            lastHidden = Date()
        }
    }

    private func show() {
        guard let item, item.isHovered, let text = item.tipText, !text.isEmpty,
              let window = item.window, let screen = window.screen else {
            hide()
            return
        }
        label.stringValue = text
        let pad = Self.padding
        // Measure the cell directly (the label's intrinsic size can be stale before layout)
        // and add a little slack so the full name always fits.
        let size = label.cell?.cellSize ?? label.intrinsicContentSize
        let width = min(ceil(size.width) + 2 + pad.width * 2, 600)
        let height = ceil(size.height) + pad.height * 2
        label.frame = CGRect(x: pad.width, y: pad.height, width: width - pad.width * 2, height: ceil(size.height))

        // The border colour is a CGColor, so resolve it against the current appearance each time.
        if let background = panel.contentView {
            background.effectiveAppearance.performAsCurrentDrawingAppearance {
                background.layer?.borderColor = NSColor.separatorColor.cgColor
            }
        }

        let anchor = window.convertToScreen(item.convert(item.bounds, to: nil))
        let visible = screen.frame
        var x = anchor.midX - width / 2
        x = min(max(x, visible.minX + 4), visible.maxX - width - 4)
        panel.setFrame(CGRect(x: x, y: anchor.maxY + 10, width: width, height: height), display: true)

        // Fade in on first appearance; when sliding between items, just move.
        if panel.isVisible {
            panel.alphaValue = 1
        } else {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 1
            }
            return
        }
        panel.orderFrontRegardless()
    }
}

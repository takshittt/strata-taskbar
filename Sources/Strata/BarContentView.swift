import AppKit

/// Draws a hairline along the top edge of the bar, re-resolving the color on appearance changes.
private final class SeparatorView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setFill()
        bounds.fill()
    }
}

/// A run of items that moves as one when dragged: the Start button, a pinned slot, or an unpinned window.
struct BarUnit {
    enum Kind: Equatable {
        case start
        case pinned(String)
        case window(CGWindowID)
    }

    let kind: Kind
    var items: [BarItemView]
}

/// The bar's root view: a blurred background with the bar items laid out on top.
final class BarContentView: NSView {
    private let background = NSVisualEffectView()
    private let separator = SeparatorView()

    private(set) var units: [BarUnit] = []
    private let startButton = StartButton()
    private var windowButtons: [CGWindowID: WindowButton] = [:]
    private var pinnedButtons: [String: PinnedButton] = [:]

    static let padding: CGFloat = 6
    static let spacing: CGFloat = 2
    static let maxWindowWidth: CGFloat = 200

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

    override func layout() {
        super.layout()
        background.frame = bounds
        separator.frame = CGRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1)
        layoutItems(animated: false)
    }

    func applySettings(_ settings: Settings) {
        background.alphaValue = CGFloat(settings.opacity)
        for unit in units { unit.items.forEach { $0.needsDisplay = true } }
        needsLayout = true
    }

    // MARK: Contents

    /// Rebuilds the unit list, reusing existing buttons by window ID so nothing flickers.
    /// Order: `[Start] [one slot per pinned app] [unpinned windows]`. A pinned slot shows the app's
    /// windows on this bar if it has any, otherwise a launcher.
    func update(pinned: [String], windows: [TrackedWindow], focusedID: CGWindowID?) {
        var used = Set<CGWindowID>()
        func button(for window: TrackedWindow) -> WindowButton {
            used.insert(window.id)
            let button = windowButtons[window.id] ?? WindowButton(window: window)
            button.update(window: window, focusedID: focusedID)
            windowButtons[window.id] = button
            return button
        }

        var next = [BarUnit(kind: .start, items: [startButton])]
        var usedPins = Set<String>()
        for bundleID in pinned {
            let appWindows = windows.filter { $0.bundleID == bundleID }
            if appWindows.isEmpty {
                usedPins.insert(bundleID)
                let launcher = pinnedButtons[bundleID] ?? PinnedButton(bundleID: bundleID)
                pinnedButtons[bundleID] = launcher
                launcher.needsDisplay = true
                next.append(BarUnit(kind: .pinned(bundleID), items: [launcher]))
            } else {
                next.append(BarUnit(kind: .pinned(bundleID), items: appWindows.map(button(for:))))
            }
        }
        let pinnedSet = Set(pinned)
        for window in windows where !pinnedSet.contains(window.bundleID ?? "") {
            next.append(BarUnit(kind: .window(window.id), items: [button(for: window)]))
        }

        for (id, button) in windowButtons where !used.contains(id) {
            button.removeFromSuperview()
            windowButtons[id] = nil
        }
        for (bundleID, launcher) in pinnedButtons where !usedPins.contains(bundleID) {
            launcher.removeFromSuperview()
            pinnedButtons[bundleID] = nil
        }
        units = next
        for unit in units {
            for item in unit.items where item.superview !== self {
                item.bar = self
                addSubview(item)
            }
        }
        layoutItems(animated: false)
    }

    // MARK: Layout

    private var itemHeight: CGFloat { max(16, bounds.height - 6) }

    /// Width of each item: square for icons, shared space for window buttons, squeezed to fit.
    private func widths(for units: [BarUnit]) -> [ObjectIdentifier: CGFloat] {
        let square = itemHeight
        let items = units.flatMap(\.items)
        let windowItems = items.filter { $0 is WindowButton }.count
        let windowCount = CGFloat(windowItems)
        let fixedWidth: CGFloat = CGFloat(items.count - windowItems) * square
        let gaps: CGFloat = CGFloat(max(0, items.count - 1)) * Self.spacing
        let available: CGFloat = bounds.width - 2 * Self.padding - fixedWidth - gaps

        var windowWidth = Settings.shared.showTitles ? Self.maxWindowWidth : square
        if windowCount > 0 {
            windowWidth = min(windowWidth, max(square, (available / windowCount).rounded(.down)))
            if windowWidth * windowCount > available { windowWidth = max(12, (available / windowCount).rounded(.down)) }
        }
        var result: [ObjectIdentifier: CGFloat] = [:]
        for item in items { result[ObjectIdentifier(item)] = item is WindowButton ? windowWidth : square }
        return result
    }

    /// Lays units out left to right (or centred), skipping `excluding` (the item being dragged).
    func layoutItems(animated: Bool, excluding dragged: BarUnit.Kind? = nil) {
        let widths = widths(for: units)
        let items = units.flatMap(\.items)
        var total: CGFloat = CGFloat(max(0, items.count - 1)) * Self.spacing
        for item in items { total += widths[ObjectIdentifier(item)] ?? 0 }
        var x: CGFloat = Self.padding
        if Settings.shared.alignment == .center { x = max(Self.padding, ((bounds.width - total) / 2).rounded()) }
        let y = ((bounds.height - itemHeight) / 2).rounded(.down)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated ? 0.18 : 0
            context.allowsImplicitAnimation = animated
            for unit in units {
                for item in unit.items {
                    let width: CGFloat = widths[ObjectIdentifier(item)] ?? 0
                    let frame = CGRect(x: x, y: y, width: width, height: itemHeight)
                    x += frame.width + Self.spacing
                    guard unit.kind != dragged, item.frame != frame else { continue }
                    if animated { item.animator().frame = frame } else { item.frame = frame }
                }
            }
        }
    }

    // MARK: Hooks used by items

    func barMenu() -> NSMenu? { BarMenus.barMenu() }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = barMenu() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    func itemHoverChanged(_ item: BarItemView, hovering: Bool) {}
    func beginDrag(_ item: BarItemView, atX x: CGFloat) {}
    func continueDrag(_ item: BarItemView, atX x: CGFloat) {}
    func endDrag(_ item: BarItemView) {}
}

/// Menus shared by the bar background, the Start button and window buttons.
enum BarMenus {
    /// Set by the app delegate once those windows exist.
    static var showSettings: (() -> Void)?
    static var showZoneEditor: (() -> Void)?
    /// Adds the Snap and Move to Zone submenus, once those features exist.
    static var windowSubmenus: ((NSMenu, TrackedWindow) -> Void)?

    static func barMenu() -> NSMenu {
        let menu = NSMenu.manual()
        menu.addItem(MenuAction("Settings…", enabled: showSettings != nil) { showSettings?() })
        menu.addItem(MenuAction("Zone Editor…", enabled: showZoneEditor != nil) { showZoneEditor?() })
        menu.addItem(.separator())
        let idle = WindowActions.appsWithoutWindows().count
        menu.addItem(MenuAction("Quit Apps Without Windows (\(idle))", enabled: idle > 0) {
            WindowActions.quitAppsWithoutWindows()
        })
        menu.addItem(.separator())
        menu.addItem(MenuAction("About Strata") { showAbout() })
        menu.addItem(MenuAction("Quit Strata") { NSApp.terminate(nil) })
        return menu
    }

    static func addWindowSubmenus(to menu: NSMenu, window: TrackedWindow) {
        windowSubmenus?(menu, window)
    }

    static func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(nil)
    }
}

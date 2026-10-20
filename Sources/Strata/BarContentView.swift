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
        case permission
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
    private let permissionButton = PermissionButton()
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
        registerForDraggedTypes([.fileURL])
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
    /// Without Accessibility the bar shows only Start and a prompt to grant it.
    func update(pinned: [String], windows: [TrackedWindow], focusedID: CGWindowID?, needsPermission: Bool = false) {
        guard drag == nil else {
            pendingUpdate = (pinned, windows, focusedID, needsPermission)
            return
        }
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
        if needsPermission {
            next.append(BarUnit(kind: .permission, items: [permissionButton]))
        } else {
            permissionButton.removeFromSuperview()
        }
        for bundleID in needsPermission ? [] : pinned {
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
        for window in windows where !needsPermission && !pinnedSet.contains(window.bundleID ?? "") {
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
        for item in items {
            result[ObjectIdentifier(item)] = item is WindowButton ? windowWidth : item is PermissionButton ? 380 : square
        }
        return result
    }

    /// Target frame of every item: left to right (or centred), in unit order.
    private func targetFrames() -> [ObjectIdentifier: CGRect] {
        let widths = widths(for: units)
        let items = units.flatMap(\.items)
        var total: CGFloat = CGFloat(max(0, items.count - 1)) * Self.spacing
        for item in items { total += widths[ObjectIdentifier(item)] ?? 0 }
        var x: CGFloat = Self.padding
        if Settings.shared.alignment == .center { x = max(Self.padding, ((bounds.width - total) / 2).rounded()) }
        let y = ((bounds.height - itemHeight) / 2).rounded(.down)

        var frames: [ObjectIdentifier: CGRect] = [:]
        for item in items {
            let width: CGFloat = widths[ObjectIdentifier(item)] ?? 0
            frames[ObjectIdentifier(item)] = CGRect(x: x, y: y, width: width, height: itemHeight)
            x += width + Self.spacing
        }
        return frames
    }

    /// Moves items to their target frames, leaving the unit being dragged where the cursor put it.
    func layoutItems(animated: Bool) {
        let frames = targetFrames()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated ? 0.18 : 0
            context.allowsImplicitAnimation = animated
            for unit in units where unit.kind != drag?.kind {
                for item in unit.items {
                    guard let frame = frames[ObjectIdentifier(item)], item.frame != frame else { continue }
                    if animated { item.animator().frame = frame } else { item.frame = frame }
                }
            }
        }
    }

    // MARK: Drag to reorder

    private struct DragState {
        let kind: BarUnit.Kind
        /// Cursor x minus the unit's left edge at the start of the drag.
        let grabOffset: CGFloat
    }

    private var drag: DragState?
    /// The newest contents that arrived mid-drag, applied when the drag ends.
    private var pendingUpdate: (pinned: [String], windows: [TrackedWindow], focusedID: CGWindowID?, needsPermission: Bool)?

    /// Units only reorder within their own group: pinned slots among pinned slots, windows among windows.
    private static func group(_ kind: BarUnit.Kind) -> Int {
        switch kind {
        case .start, .permission: return 0
        case .pinned: return 1
        case .window: return 2
        }
    }

    func beginDrag(_ item: BarItemView, atX x: CGFloat) {
        guard let unit = units.first(where: { $0.items.contains { $0 === item } }), unit.kind != .start,
              let first = unit.items.first else { return }
        HoverTip.shared.hide()
        drag = DragState(kind: unit.kind, grabOffset: x - first.frame.minX)
        for item in unit.items { addSubview(item, positioned: .above, relativeTo: nil) }
    }

    func continueDrag(_ item: BarItemView, atX x: CGFloat) {
        guard let drag, let index = units.firstIndex(where: { $0.kind == drag.kind }) else { return }
        let group = Self.group(drag.kind)
        let groupIndices = units.indices.filter { Self.group(units[$0].kind) == group }
        let frames = targetFrames()
        func left(_ unit: BarUnit) -> CGFloat { frames[ObjectIdentifier(unit.items[0])]?.minX ?? 0 }
        func right(_ unit: BarUnit) -> CGFloat { frames[ObjectIdentifier(unit.items[unit.items.count - 1])]?.maxX ?? 0 }

        // Follow the cursor, but stay inside the group.
        guard let firstIndex = groupIndices.first, let lastIndex = groupIndices.last else { return }
        let unit = units[index]
        let width = right(unit) - left(unit)
        let minX = left(units[firstIndex])
        let maxX = right(units[lastIndex]) - width
        var originX = min(max(x - drag.grabOffset, minX), maxX)
        for item in unit.items {
            item.frame.origin.x = originX
            originX += item.frame.width + Self.spacing
        }

        // Swap with a neighbour once the dragged unit's centre passes the neighbour's centre.
        // Use the unclamped position, so dragging past the group's edge still reaches the end slot.
        let center = x - drag.grabOffset + width / 2
        func midX(_ i: Int) -> CGFloat { (left(units[i]) + right(units[i])) / 2 }
        var target = index
        if index > firstIndex, center < midX(index - 1) {
            target = index - 1
        } else if index < lastIndex, center > midX(index + 1) {
            target = index + 1
        }
        if target != index {
            units.swapAt(index, target)
            layoutItems(animated: true)
        }
    }

    func endDrag(_ item: BarItemView) {
        guard let drag else { return }
        self.drag = nil
        layoutItems(animated: true)
        switch drag.kind {
        case .pinned:
            Settings.shared.pinnedBundleIDs = units.compactMap {
                if case .pinned(let bundleID) = $0.kind { return bundleID }
                return nil
            }
        case .window:
            WindowTracker.shared.applyOrder(units.compactMap {
                if case .window(let id) = $0.kind { return id }
                return nil
            })
        case .start, .permission:
            break
        }
        if let pending = pendingUpdate {
            pendingUpdate = nil
            update(pinned: pending.pinned, windows: pending.windows, focusedID: pending.focusedID,
                   needsPermission: pending.needsPermission)
        }
    }

    // MARK: Dropping apps to pin them

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        DroppedFiles.appBundleIDs(DroppedFiles.urls(sender)) == nil ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let bundleIDs = DroppedFiles.appBundleIDs(DroppedFiles.urls(sender)) else { return false }
        pin(bundleIDs, at: nil)
        return true
    }

    /// Pins apps in front of the pinned slot holding `item`, or at the end.
    func pin(_ bundleIDs: [String], at item: BarItemView?) {
        let settings = Settings.shared
        var index: Int?
        if let item, let unit = units.first(where: { $0.items.contains { $0 === item } }),
           case .pinned(let bundleID) = unit.kind {
            index = settings.pinnedBundleIDs.firstIndex(of: bundleID)
        }
        Log.info("pinning \(bundleIDs) at \(index.map(String.init) ?? "end")")
        settings.pin(bundleIDs, at: index)
    }

    // MARK: Hooks used by items

    func barMenu() -> NSMenu? { BarMenus.barMenu() }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = barMenu() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    func itemHoverChanged(_ item: BarItemView, hovering: Bool) {
        if hovering, drag == nil {
            HoverTip.shared.hover(item)
        } else {
            HoverTip.shared.leave(item)
        }
    }
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
        WindowActions.activateSelf()
        let info = Bundle.main.infoDictionary ?? [:]
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Strata",
            .applicationVersion: info["CFBundleShortVersionString"] as? String ?? "",
            .version: info["CFBundleVersion"] as? String ?? "",
            .credits: NSAttributedString(
                string: "A Windows-style taskbar for macOS.",
                attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
            ),
        ])
    }
}

import AppKit

/// The 18 snap actions (spec §3.3, §3.4).
enum SnapAction: String, CaseIterable, Codable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case firstThird, centerThird, lastThird, firstTwoThirds, lastTwoThirds
    case maximize, center, restore
    case previousDisplay, nextDisplay

    var title: String {
        switch self {
        case .leftHalf: return "Left Half"
        case .rightHalf: return "Right Half"
        case .topHalf: return "Top Half"
        case .bottomHalf: return "Bottom Half"
        case .topLeft: return "Top Left"
        case .topRight: return "Top Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        case .firstThird: return "First Third"
        case .centerThird: return "Center Third"
        case .lastThird: return "Last Third"
        case .firstTwoThirds: return "First Two Thirds"
        case .lastTwoThirds: return "Last Two Thirds"
        case .maximize: return "Maximize"
        case .center: return "Center"
        case .restore: return "Restore"
        case .previousDisplay: return "Previous Display"
        case .nextDisplay: return "Next Display"
        }
    }

    /// Menu sections, separated by dividers.
    static let menuGroups: [[SnapAction]] = [
        [.leftHalf, .rightHalf, .topHalf, .bottomHalf],
        [.topLeft, .topRight, .bottomLeft, .bottomRight],
        [.firstThird, .centerThird, .lastThird, .firstTwoThirds, .lastTwoThirds],
        [.maximize, .center, .restore],
        [.previousDisplay, .nextDisplay],
    ]

    /// Fixed in v1: ⌃⌥ + key, following Rectangle's conventions.
    var defaultShortcut: Shortcut {
        let ctrlOpt = Shortcut.control | Shortcut.option
        switch self {
        case .leftHalf: return Shortcut(keyCode: KeyCode.leftArrow, modifiers: ctrlOpt)
        case .rightHalf: return Shortcut(keyCode: KeyCode.rightArrow, modifiers: ctrlOpt)
        case .topHalf: return Shortcut(keyCode: KeyCode.upArrow, modifiers: ctrlOpt)
        case .bottomHalf: return Shortcut(keyCode: KeyCode.downArrow, modifiers: ctrlOpt)
        case .topLeft: return Shortcut(keyCode: KeyCode.u, modifiers: ctrlOpt)
        case .topRight: return Shortcut(keyCode: KeyCode.i, modifiers: ctrlOpt)
        case .bottomLeft: return Shortcut(keyCode: KeyCode.j, modifiers: ctrlOpt)
        case .bottomRight: return Shortcut(keyCode: KeyCode.k, modifiers: ctrlOpt)
        case .firstThird: return Shortcut(keyCode: KeyCode.d, modifiers: ctrlOpt)
        case .centerThird: return Shortcut(keyCode: KeyCode.f, modifiers: ctrlOpt)
        case .lastThird: return Shortcut(keyCode: KeyCode.g, modifiers: ctrlOpt)
        case .firstTwoThirds: return Shortcut(keyCode: KeyCode.e, modifiers: ctrlOpt)
        case .lastTwoThirds: return Shortcut(keyCode: KeyCode.t, modifiers: ctrlOpt)
        case .maximize: return Shortcut(keyCode: KeyCode.returnKey, modifiers: ctrlOpt)
        case .center: return Shortcut(keyCode: KeyCode.c, modifiers: ctrlOpt)
        case .restore: return Shortcut(keyCode: KeyCode.delete, modifiers: ctrlOpt)
        case .previousDisplay: return Shortcut(keyCode: KeyCode.leftArrow, modifiers: ctrlOpt | Shortcut.command)
        case .nextDisplay: return Shortcut(keyCode: KeyCode.rightArrow, modifiers: ctrlOpt | Shortcut.command)
        }
    }

    /// The region as fractions of the work area (top-left origin). Thirds run along the long edge,
    /// so on a portrait display they stack vertically. `nil` for actions that aren't a fixed region.
    func unitRect(portrait: Bool) -> CGRect? {
        func third(_ start: CGFloat, _ length: CGFloat) -> CGRect {
            portrait ? CGRect(x: 0, y: start, width: 1, height: length) : CGRect(x: start, y: 0, width: length, height: 1)
        }
        switch self {
        case .leftHalf: return CGRect(x: 0, y: 0, width: 0.5, height: 1)
        case .rightHalf: return CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        case .topHalf: return CGRect(x: 0, y: 0, width: 1, height: 0.5)
        case .bottomHalf: return CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
        case .topLeft: return CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        case .topRight: return CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
        case .bottomLeft: return CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)
        case .bottomRight: return CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        case .firstThird: return third(0, 1.0 / 3)
        case .centerThird: return third(1.0 / 3, 1.0 / 3)
        case .lastThird: return third(2.0 / 3, 1.0 / 3)
        case .firstTwoThirds: return third(0, 2.0 / 3)
        case .lastTwoThirds: return third(1.0 / 3, 2.0 / 3)
        case .maximize: return CGRect(x: 0, y: 0, width: 1, height: 1)
        case .center, .restore, .previousDisplay, .nextDisplay: return nil
        }
    }

    /// Target frame in AX coordinates for a window currently at `current`, inside work area `area`.
    /// `gap` leaves the same spacing at the screen edges and between neighbouring snapped windows.
    /// `nil` for restore and the display moves, which aren't computed from the area.
    func frame(in area: CGRect, current: CGRect, gap: CGFloat) -> CGRect? {
        if self == .center {
            let width = min(current.width, area.width)
            let height = min(current.height, area.height)
            return CGRect(x: (area.midX - width / 2).rounded(), y: (area.midY - height / 2).rounded(), width: width, height: height)
        }
        guard let unit = unitRect(portrait: area.height > area.width) else { return nil }
        return Self.place(unit, in: area, gap: gap)
    }

    /// Maps a unit rect into `area`, with half the gap around the area and half around each cell.
    static func place(_ unit: CGRect, in area: CGRect, gap: CGFloat) -> CGRect {
        let inner = area.insetBy(dx: gap / 2, dy: gap / 2)
        let minX = (inner.minX + unit.minX * inner.width + gap / 2).rounded()
        let minY = (inner.minY + unit.minY * inner.height + gap / 2).rounded()
        let maxX = (inner.minX + unit.maxX * inner.width - gap / 2).rounded()
        let maxY = (inner.minY + unit.maxY * inner.height - gap / 2).rounded()
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

/// Moves and resizes other apps' windows (spec §3.3).
enum WindowMover {
    /// Each window's frame before its first snap, for Restore.
    private static var restoreFrames: [CGWindowID: CGRect] = [:]

    static func perform(_ action: SnapAction, on ref: WindowRef? = WindowRef.focused()) {
        guard let ref, let current = ref.frame, let screen = ScreenGeometry.screen(for: current) else { return }
        guard AX.bool(ref.element, "AXFullScreen") != true else { return }
        switch action {
        case .restore:
            guard let frame = restoreFrames.removeValue(forKey: ref.id) else { return }
            setFrame(ref, frame)
        case .previousDisplay:
            move(ref, byDisplays: -1)
        case .nextDisplay:
            move(ref, byDisplays: 1)
        default:
            let gap = CGFloat(Settings.shared.windowGap)
            guard let frame = action.frame(in: ScreenGeometry.axWorkArea(screen), current: current, gap: gap) else { return }
            apply(ref, frame)
        }
    }

    /// Moves a window to `frame`, remembering where it was before its first snap.
    static func apply(_ ref: WindowRef, _ frame: CGRect) {
        if restoreFrames[ref.id] == nil, let current = ref.frame { restoreFrames[ref.id] = current }
        setFrame(ref, frame)
    }

    /// Displays left to right (then top to bottom), wrapping around.
    static func move(_ ref: WindowRef, byDisplays offset: Int) {
        let screens = NSScreen.screens.sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
        guard screens.count > 1, let current = ref.frame, let screen = ScreenGeometry.screen(for: current),
              let index = screens.firstIndex(of: screen) else { return }
        move(ref, to: screens[(index + offset + screens.count) % screens.count])
    }

    /// Moves a window to another display, keeping its position and size relative to the work area.
    static func move(_ ref: WindowRef, to target: NSScreen) {
        guard let current = ref.frame, let screen = ScreenGeometry.screen(for: current), screen != target else { return }
        let from = ScreenGeometry.axWorkArea(screen)
        let to = ScreenGeometry.axWorkArea(target)
        let width = min(to.width, current.width / from.width * to.width)
        let height = min(to.height, current.height / from.height * to.height)
        var x = to.minX + (current.minX - from.minX) / from.width * to.width
        var y = to.minY + (current.minY - from.minY) / from.height * to.height
        x = min(max(x, to.minX), to.maxX - width)
        y = min(max(y, to.minY), to.maxY - height)
        apply(ref, CGRect(x: x, y: y, width: width, height: height).integral)
    }

    /// Sets the frame with `AXEnhancedUserInterface` off, which Chromium and Electron apps need.
    static func setFrame(_ ref: WindowRef, _ frame: CGRect) {
        let app = AX.app(ref.pid)
        let enhanced = AX.bool(app, "AXEnhancedUserInterface") == true
        if enhanced { AX.set(app, "AXEnhancedUserInterface", kCFBooleanFalse) }
        if AX.bool(ref.element, kAXMinimizedAttribute) == true {
            AX.set(ref.element, kAXMinimizedAttribute, kCFBooleanFalse)
        }
        AX.setFrame(ref.element, frame)
        if enhanced { AX.set(app, "AXEnhancedUserInterface", kCFBooleanTrue) }
        WindowTracker.shared.scheduleRefresh()
    }

    /// The "Snap" submenu for a window's context menu.
    static func snapMenuItem(for ref: WindowRef) -> NSMenuItem {
        let menu = NSMenu.manual("Snap")
        for (index, group) in SnapAction.menuGroups.enumerated() {
            if index > 0 { menu.addItem(.separator()) }
            for action in group {
                let item = MenuAction(action.title) { perform(action, on: ref) }
                if let (key, modifiers) = action.defaultShortcut.menuKeyEquivalent {
                    item.keyEquivalent = key
                    item.keyEquivalentModifierMask = modifiers
                }
                menu.addItem(item)
            }
        }
        let item = NSMenuItem(title: "Snap", action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}

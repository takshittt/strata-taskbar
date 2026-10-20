import AppKit
import Combine

/// A rectangle of grid cells.
struct CellRange: Codable, Hashable {
    var column: Int
    var row: Int
    var columnSpan: Int
    var rowSpan: Int

    init(column: Int, row: Int, columnSpan: Int = 1, rowSpan: Int = 1) {
        self.column = column
        self.row = row
        self.columnSpan = columnSpan
        self.rowSpan = rowSpan
    }

    /// The range covering two corner cells, in any order.
    init(from a: (column: Int, row: Int), to b: (column: Int, row: Int)) {
        self.init(column: min(a.column, b.column), row: min(a.row, b.row),
                  columnSpan: abs(a.column - b.column) + 1, rowSpan: abs(a.row - b.row) + 1)
    }

    func overlaps(_ other: CellRange) -> Bool {
        column < other.column + other.columnSpan && other.column < column + columnSpan
            && row < other.row + other.rowSpan && other.row < row + rowSpan
    }
}

struct Zone: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var cells: CellRange
    var shortcut: Shortcut?
}

/// A grid (column and row fractions) plus named zones over it, for one display.
struct ZoneLayout: Codable, Equatable {
    var columns: [Double]
    var rows: [Double]
    var zones: [Zone]

    static let `default` = ZoneLayout(columns: equal(3), rows: equal(2), zones: [])

    static func equal(_ count: Int) -> [Double] {
        Array(repeating: 1 / Double(max(1, count)), count: max(1, count))
    }

    /// The cells' rectangle as fractions of the work area (top-left origin).
    func unitRect(_ cells: CellRange) -> CGRect {
        func span(_ fractions: [Double], _ start: Int, _ count: Int) -> (CGFloat, CGFloat) {
            let lower = max(0, min(start, fractions.count))
            let upper = max(lower, min(start + count, fractions.count))
            let offset = fractions[..<lower].reduce(0, +)
            return (CGFloat(offset), CGFloat(fractions[lower..<upper].reduce(0, +)))
        }
        let (x, width) = span(columns, cells.column, cells.columnSpan)
        let (y, height) = span(rows, cells.row, cells.rowSpan)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Changes the grid size. Existing sizes are kept where possible; zones that no longer fit are
    /// clipped, and dropped if they start outside the new grid.
    func resized(columns newColumns: Int, rows newRows: Int) -> ZoneLayout {
        func resize(_ fractions: [Double], to count: Int) -> [Double] {
            let count = max(1, count)
            if count == fractions.count { return fractions }
            if count < fractions.count {
                let kept = Array(fractions.prefix(count))
                let total = kept.reduce(0, +)
                return total > 0 ? kept.map { $0 / total } : Self.equal(count)
            }
            // New tracks get an equal share; existing ones shrink proportionally to make room.
            let scale = Double(fractions.count) / Double(count)
            return fractions.map { $0 * scale } + Array(repeating: 1 / Double(count), count: count - fractions.count)
        }
        var layout = self
        layout.columns = resize(columns, to: newColumns)
        layout.rows = resize(rows, to: newRows)
        layout.zones = zones.compactMap { zone in
            var zone = zone
            guard zone.cells.column < layout.columns.count, zone.cells.row < layout.rows.count else { return nil }
            zone.cells.columnSpan = min(zone.cells.columnSpan, layout.columns.count - zone.cells.column)
            zone.cells.rowSpan = min(zone.cells.rowSpan, layout.rows.count - zone.cells.row)
            return zone
        }
        return layout
    }

    /// "Zone N" with the smallest N not already used.
    func nextZoneName() -> String {
        let names = Set(zones.map(\.name))
        var n = 1
        while names.contains("Zone \(n)") { n += 1 }
        return "Zone \(n)"
    }

    func zone(atUnit point: CGPoint) -> Zone? {
        zones.first { unitRect($0.cells).contains(point) }
    }

    func canAdd(_ cells: CellRange) -> Bool {
        cells.column + cells.columnSpan <= columns.count && cells.row + cells.rowSpan <= rows.count
            && !zones.contains { $0.cells.overlaps(cells) }
    }

    /// The cell containing a unit-space point.
    func cell(atUnit point: CGPoint) -> (column: Int, row: Int) {
        func index(_ fractions: [Double], _ value: CGFloat) -> Int {
            var edge: CGFloat = 0
            for (i, fraction) in fractions.enumerated() {
                edge += CGFloat(fraction)
                if value < edge { return i }
            }
            return fractions.count - 1
        }
        return (index(columns, point.x), index(rows, point.y))
    }
}

/// Zone layouts, stored as JSON in UserDefaults and keyed by display UUID (stable across reconnects).
final class ZoneStore: ObservableObject {
    static let shared = ZoneStore()
    private static let key = "zoneLayouts"

    @Published private(set) var layouts: [String: ZoneLayout] = [:]

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([String: ZoneLayout].self, from: data) {
            layouts = decoded
        }
    }

    func layout(for displayKey: String) -> ZoneLayout {
        layouts[displayKey] ?? .default
    }

    func set(_ layout: ZoneLayout, for displayKey: String) {
        let shortcutsChanged = bindings(layouts[displayKey]) != bindings(layout)
        layouts[displayKey] = layout
        if let data = try? JSONEncoder().encode(layouts) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
        if shortcutsChanged { HotKeys.shared.registerAll() }
    }

    private func bindings(_ layout: ZoneLayout?) -> [UUID: Shortcut] {
        var result: [UUID: Shortcut] = [:]
        for zone in layout?.zones ?? [] { result[zone.id] = zone.shortcut }
        return result
    }

    /// Every zone shortcut, for HotKeys.
    var shortcutBindings: [(HotKeyTarget, Shortcut)] {
        layouts.flatMap { key, layout in
            layout.zones.compactMap { zone in zone.shortcut.map { (.zone(display: key, zone: zone.id), $0) } }
        }
    }

    func zone(_ id: UUID, display: String) -> Zone? {
        layouts[display]?.zones.first { $0.id == id }
    }
}

extension WindowMover {
    /// Moves a window into a zone on the given display (which may not be the window's current one).
    static func move(_ ref: WindowRef, to zone: Zone, in layout: ZoneLayout, on screen: NSScreen) {
        let frame = SnapAction.place(layout.unitRect(zone.cells), in: ScreenGeometry.axWorkArea(screen),
                                     gap: CGFloat(Settings.shared.windowGap))
        apply(ref, frame)
    }

    static func moveFocused(toZone id: UUID, display: String) {
        guard let ref = WindowRef.focused(),
              let screen = NSScreen.screens.first(where: { ScreenGeometry.displayKey($0) == display }),
              let zone = ZoneStore.shared.zone(id, display: display) else { return }
        move(ref, to: zone, in: ZoneStore.shared.layout(for: display), on: screen)
    }

    /// The "Move to Zone" submenu, or `nil` if no display has zones.
    static func zoneMenuItem(for ref: WindowRef) -> NSMenuItem? {
        let screens = NSScreen.screens.compactMap { screen -> (NSScreen, String, ZoneLayout)? in
            guard let key = ScreenGeometry.displayKey(screen) else { return nil }
            let layout = ZoneStore.shared.layout(for: key)
            return layout.zones.isEmpty ? nil : (screen, key, layout)
        }
        guard !screens.isEmpty else { return nil }
        let menu = NSMenu.manual("Move to Zone")
        for (index, (screen, _, layout)) in screens.enumerated() {
            if screens.count > 1 {
                if index > 0 { menu.addItem(.separator()) }
                menu.addHeader(screen.localizedName)
            }
            for zone in layout.zones {
                let item = MenuAction(zone.name) { move(ref, to: zone, in: layout, on: screen) }
                if let (key, modifiers) = zone.shortcut?.menuKeyEquivalent {
                    item.keyEquivalent = key
                    item.keyEquivalentModifierMask = modifiers
                }
                menu.addItem(item)
            }
        }
        let item = NSMenuItem(title: "Move to Zone", action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}

// MARK: Overlays

/// Draws a layout's zones over a display's work area, with one zone highlighted.
private final class ZoneOverlayView: NSView {
    var layout = ZoneLayout.default
    /// Work area in this view's coordinates.
    var workArea = CGRect.zero
    var highlighted: UUID?

    override func draw(_ dirtyRect: NSRect) {
        let accent = NSColor.controlAccentColor
        for zone in layout.zones {
            let unit = layout.unitRect(zone.cells)
            let rect = CGRect(x: workArea.minX + unit.minX * workArea.width,
                              y: workArea.maxY - unit.maxY * workArea.height,
                              width: unit.width * workArea.width, height: unit.height * workArea.height).insetBy(dx: 6, dy: 6)
            let path = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
            let isHighlighted = zone.id == highlighted
            accent.withAlphaComponent(isHighlighted ? 0.45 : 0.15).setFill()
            path.fill()
            accent.withAlphaComponent(0.9).setStroke()
            path.lineWidth = isHighlighted ? 3 : 1.5
            path.stroke()

            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
                .foregroundColor: NSColor.white,
                .strokeColor: NSColor.black.withAlphaComponent(0.6),
                .strokeWidth: -2,
            ]
            let size = zone.name.size(withAttributes: attributes)
            zone.name.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attributes)
        }
    }
}

/// A click-through, full-screen panel showing a display's zones.
final class ZoneOverlay {
    private var panel: NSPanel?
    private let view = ZoneOverlayView()
    private var hideTimer: Timer?

    func show(_ layout: ZoneLayout, on screen: NSScreen, highlighted: UUID?) {
        hideTimer?.invalidate()
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if panel.frame != screen.frame { panel.setFrame(screen.frame, display: false) }
        let area = ScreenGeometry.workArea(screen)
        view.workArea = area.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
        view.layout = layout
        view.highlighted = highlighted
        view.needsDisplay = true
        panel.orderFrontRegardless()
    }

    /// Shows the layout, then hides it after `duration`.
    func preview(_ layout: ZoneLayout, on screen: NSScreen, duration: TimeInterval = 1.5) {
        show(layout, on: screen, highlighted: nil)
        hideTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in self?.hide() }
    }

    func hide() {
        hideTimer?.invalidate()
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.contentView = view
        return panel
    }
}

/// Shift-drag a window to show the zones under the cursor; release to drop it into the highlighted zone.
final class ZoneGridOverlay {
    static let shared = ZoneGridOverlay()

    private let overlay = ZoneOverlay()
    private var monitor: Any?
    /// The window being dragged, captured on the first drag event (the click has focused it by then).
    private var dragged: WindowRef?
    private var startOrigin: CGPoint?
    /// True once the window is actually moving (not a shift-drag inside its content).
    private var windowMoving = false
    private var lastProbe: CFAbsoluteTime = 0
    private var target: (screen: NSScreen, layout: ZoneLayout, zone: Zone?)?

    func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .flagsChanged]) {
            [weak self] event in self?.handle(event)
        }
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            reset()
        case .leftMouseDragged:
            if dragged == nil {
                dragged = WindowRef.focused()
                startOrigin = dragged?.frame?.origin
            }
            guard NSEvent.modifierFlags.contains(.shift) else {
                if target != nil { clearTarget() }
                return
            }
            if !windowMoving {
                // Probing AX on every drag event is wasteful; every 50 ms is plenty.
                let now = CFAbsoluteTimeGetCurrent()
                guard now - lastProbe > 0.05 else { return }
                lastProbe = now
                guard let origin = dragged?.frame?.origin, let start = startOrigin, origin != start else { return }
                windowMoving = true
            }
            updateTarget(at: NSEvent.mouseLocation)
        case .flagsChanged:
            if !event.modifierFlags.contains(.shift), target != nil { clearTarget() }
        case .leftMouseUp:
            if let target, let zone = target.zone, let ref = dragged {
                // Let the app finish its own drag before we move the window.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    WindowMover.move(ref, to: zone, in: target.layout, on: target.screen)
                }
            }
            reset()
        default:
            break
        }
    }

    private func updateTarget(at point: CGPoint) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }),
              let key = ScreenGeometry.displayKey(screen) else { return clearTarget() }
        let layout = ZoneStore.shared.layout(for: key)
        guard !layout.zones.isEmpty else { return clearTarget() }
        let area = ScreenGeometry.workArea(screen)
        let unit = CGPoint(x: (point.x - area.minX) / area.width, y: (area.maxY - point.y) / area.height)
        let zone = layout.zone(atUnit: unit)
        target = (screen, layout, zone)
        overlay.show(layout, on: screen, highlighted: zone?.id)
    }

    private func clearTarget() {
        target = nil
        overlay.hide()
    }

    private func reset() {
        clearTarget()
        dragged = nil
        startOrigin = nil
        windowMoving = false
    }
}

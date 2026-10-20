import AppKit
import SwiftUI

/// Editing state for one display's zone layout. Every change is saved straight to `ZoneStore`.
final class ZoneEditorModel: ObservableObject {
    struct Display: Identifiable, Hashable {
        let id: String
        let name: String
    }

    @Published var displays: [Display] = []
    @Published var displayKey: String = "" {
        didSet {
            guard displayKey != oldValue else { return }
            layout = ZoneStore.shared.layout(for: displayKey)
            selection = nil
        }
    }
    @Published var layout = ZoneLayout.default {
        didSet { if layout != oldValue, !displayKey.isEmpty { ZoneStore.shared.set(layout, for: displayKey) } }
    }
    @Published var selection: CellRange?
    @Published private(set) var recordingZoneID: UUID?
    /// Track sizes when a divider drag began. (Lives here: SwiftUI's `@State` macro needs Xcode's plugin.)
    var dividerBase: [Double]?

    private var keyMonitor: Any?
    let overlay = ZoneOverlay()

    init() {
        reloadDisplays()
    }

    func reloadDisplays() {
        displays = NSScreen.screens.compactMap { screen in
            ScreenGeometry.displayKey(screen).map { Display(id: $0, name: screen.localizedName) }
        }
        if !displays.contains(where: { $0.id == displayKey }) {
            displayKey = displays.first?.id ?? ""
        }
    }

    var screen: NSScreen? {
        NSScreen.screens.first { ScreenGeometry.displayKey($0) == displayKey }
    }

    /// Width over height of the work area, so the grid editor has the display's shape.
    var aspectRatio: CGFloat {
        guard let screen else { return 16 / 10 }
        let area = ScreenGeometry.workArea(screen)
        return area.height > 0 ? area.width / area.height : 16 / 10
    }

    var columnCount: Int {
        get { layout.columns.count }
        set { layout = layout.resized(columns: newValue, rows: layout.rows.count); selection = nil }
    }

    var rowCount: Int {
        get { layout.rows.count }
        set { layout = layout.resized(columns: layout.columns.count, rows: newValue); selection = nil }
    }

    func equalize() {
        layout.columns = ZoneLayout.equal(layout.columns.count)
        layout.rows = ZoneLayout.equal(layout.rows.count)
    }

    var canAddSelection: Bool {
        guard let selection else { return false }
        return layout.canAdd(selection)
    }

    func addZoneFromSelection() {
        guard let selection, layout.canAdd(selection) else { return }
        layout.zones.append(Zone(name: layout.nextZoneName(), cells: selection))
        self.selection = nil
    }

    func rename(_ id: UUID, to name: String) {
        guard let index = layout.zones.firstIndex(where: { $0.id == id }) else { return }
        layout.zones[index].name = name
    }

    func delete(_ id: UUID) {
        if recordingZoneID == id { stopRecording() }
        layout.zones.removeAll { $0.id == id }
    }

    func preview() {
        guard let screen else { return }
        overlay.preview(layout, on: screen)
    }

    // MARK: Shortcut recording

    /// Records the next key-down as the zone's shortcut: Esc cancels, ⌫ clears.
    /// Registered hotkeys are suspended meanwhile so they don't fire mid-capture.
    func startRecording(_ id: UUID) {
        stopRecording()
        recordingZoneID = id
        HotKeys.shared.suspend()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let zoneID = self.recordingZoneID,
                  let index = self.layout.zones.firstIndex(where: { $0.id == zoneID }) else { return event }
            switch UInt32(event.keyCode) {
            case KeyCode.escape:
                self.stopRecording()
            case KeyCode.delete, KeyCode.forwardDelete:
                self.layout.zones[index].shortcut = nil
                self.stopRecording()
            default:
                guard let shortcut = Shortcut(event: event) else {
                    NSSound.beep()
                    return nil
                }
                self.layout.zones[index].shortcut = shortcut
                self.stopRecording()
            }
            return nil
        }
    }

    func stopRecording() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        guard recordingZoneID != nil else { return }
        recordingZoneID = nil
        HotKeys.shared.resume()
    }
}

/// The grid: drag across cells to select, drag the dividers to resize columns and rows.
private struct ZoneGridView: View {
    @ObservedObject var model: ZoneEditorModel

    private static let minFraction = 0.05

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .underPageBackgroundColor))

                // Cells
                ForEach(0..<model.layout.columns.count, id: \.self) { column in
                    ForEach(0..<model.layout.rows.count, id: \.self) { row in
                        let rect = scaled(model.layout.unitRect(CellRange(column: column, row: row)), size)
                        Rectangle()
                            .strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1)
                            .frame(width: rect.width, height: rect.height)
                            .offset(x: rect.minX, y: rect.minY)
                    }
                }

                // Zones
                ForEach(model.layout.zones) { zone in
                    let rect = scaled(model.layout.unitRect(zone.cells), size).insetBy(dx: 3, dy: 3)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor.opacity(0.25))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor, lineWidth: 1.5))
                        .overlay(Text(zone.name).font(.headline))
                        .frame(width: max(0, rect.width), height: max(0, rect.height))
                        .offset(x: rect.minX, y: rect.minY)
                        .allowsHitTesting(false)
                }

                // Selection
                if let selection = model.selection {
                    let rect = scaled(model.layout.unitRect(selection), size)
                    Rectangle()
                        .fill((model.canAddSelection ? Color.accentColor : Color.red).opacity(0.3))
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                        .allowsHitTesting(false)
                }

                dividers(size)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        model.selection = CellRange(from: cell(at: value.startLocation, size), to: cell(at: value.location, size))
                    }
            )
        }
        .aspectRatio(model.aspectRatio, contentMode: .fit)
    }

    /// Draggable handles on every inner column and row boundary.
    @ViewBuilder
    private func dividers(_ size: CGSize) -> some View {
        let columns = model.layout.columns
        let rows = model.layout.rows
        ForEach(0..<max(0, columns.count - 1), id: \.self) { index in
            let x = CGFloat(columns[...index].reduce(0, +)) * size.width
            Rectangle()
                .fill(Color.accentColor.opacity(0.001))
                .overlay(Rectangle().fill(Color.accentColor.opacity(0.6)).frame(width: 2))
                .frame(width: 10, height: size.height)
                .offset(x: x - 5)
                .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
                .gesture(dividerDrag(index: index, isColumn: true, length: size.width))
        }
        ForEach(0..<max(0, rows.count - 1), id: \.self) { index in
            let y = CGFloat(rows[...index].reduce(0, +)) * size.height
            Rectangle()
                .fill(Color.accentColor.opacity(0.001))
                .overlay(Rectangle().fill(Color.accentColor.opacity(0.6)).frame(height: 2))
                .frame(width: size.width, height: 10)
                .offset(y: y - 5)
                .onHover { inside in if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() } }
                .gesture(dividerDrag(index: index, isColumn: false, length: size.height))
        }
    }

    /// Moves the boundary after track `index`, trading size between it and the next track.
    private func dividerDrag(index: Int, isColumn: Bool, length: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let base = model.dividerBase ?? (isColumn ? model.layout.columns : model.layout.rows)
                model.dividerBase = base
                let pair = base[index] + base[index + 1]
                let delta = Double((isColumn ? value.translation.width : value.translation.height) / length)
                let first = min(max(base[index] + delta, Self.minFraction), pair - Self.minFraction)
                var updated = base
                updated[index] = first
                updated[index + 1] = pair - first
                if isColumn { model.layout.columns = updated } else { model.layout.rows = updated }
            }
            .onEnded { _ in model.dividerBase = nil }
    }

    private func scaled(_ unit: CGRect, _ size: CGSize) -> CGRect {
        CGRect(x: unit.minX * size.width, y: unit.minY * size.height, width: unit.width * size.width, height: unit.height * size.height)
    }

    private func cell(at point: CGPoint, _ size: CGSize) -> (column: Int, row: Int) {
        model.layout.cell(atUnit: CGPoint(x: point.x / max(1, size.width), y: point.y / max(1, size.height)))
    }
}

struct ZoneEditorView: View {
    @ObservedObject var model: ZoneEditorModel
    @ObservedObject private var hotKeys = HotKeys.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Picker("Display", selection: $model.displayKey) {
                    ForEach(model.displays) { Text($0.name).tag($0.id) }
                }
                .frame(maxWidth: 280)
                Spacer()
                Stepper("Columns: \(model.columnCount)", value: $model.columnCount, in: 1...12)
                Stepper("Rows: \(model.rowCount)", value: $model.rowCount, in: 1...12)
                Button("Equalize", action: model.equalize)
            }

            ZoneGridView(model: model)
                .frame(maxWidth: .infinity, minHeight: 240)

            HStack {
                Button("Add Zone from Selection", action: model.addZoneFromSelection)
                    .disabled(!model.canAddSelection)
                if model.selection != nil, !model.canAddSelection {
                    Text("The selection overlaps an existing zone.").font(.caption).foregroundStyle(.red)
                } else {
                    Text("Drag across the grid to select cells.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Preview on Display", action: model.preview)
            }

            List {
                if model.layout.zones.isEmpty {
                    Text("No zones yet.").foregroundStyle(.secondary)
                }
                ForEach(model.layout.zones) { zone in
                    HStack {
                        TextField("Name", text: Binding(get: { zone.name }, set: { model.rename(zone.id, to: $0) }))
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 220)
                        Spacer()
                        if hotKeys.unavailable.contains(.zone(display: model.displayKey, zone: zone.id)) {
                            Text("in use elsewhere").font(.caption).foregroundStyle(.orange)
                        }
                        Button(shortcutLabel(zone)) { model.startRecording(zone.id) }
                            .monospaced()
                            .frame(minWidth: 150)
                        Button(role: .destructive) {
                            model.delete(zone.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Delete zone")
                    }
                }
            }
            .frame(minHeight: 150)
            Text("While recording: press a shortcut with ⌘, ⌃ or ⌥. Esc cancels, ⌫ clears.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(minWidth: 720, minHeight: 640)
    }

    private func shortcutLabel(_ zone: Zone) -> String {
        if model.recordingZoneID == zone.id { return "Type shortcut…" }
        return zone.shortcut?.displayString ?? "Record Shortcut"
    }
}

/// The Zone Editor window. Closing it stops any shortcut recording in progress.
final class ZoneEditorWindow: NSObject, NSWindowDelegate {
    static let shared = ZoneEditorWindow()
    private var window: NSWindow?
    private let model = ZoneEditorModel()

    func show() {
        model.reloadDisplays()
        if window == nil {
            let window = KeyCommandWindow(contentViewController: NSHostingController(rootView: ZoneEditorView(model: model)))
            window.title = "Strata Zone Editor"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(CGSize(width: 760, height: 700))
            window.center()
            window.delegate = self
            self.window = window
        }
        WindowActions.activateSelf()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        model.stopRecording()
        model.overlay.hide()
    }
}

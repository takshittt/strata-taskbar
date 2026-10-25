import Foundation
import Testing
@testable import Strata

struct ZoneLayoutTests {
    let layout = ZoneLayout(columns: [0.25, 0.5, 0.25], rows: [0.5, 0.5], zones: [
        Zone(name: "Left", cells: CellRange(column: 0, row: 0, columnSpan: 1, rowSpan: 2)),
        Zone(name: "Right Top", cells: CellRange(column: 1, row: 0, columnSpan: 2, rowSpan: 1)),
        Zone(name: "Corner", cells: CellRange(column: 2, row: 1)),
    ])

    @Test func unitRect() {
        #expect(layout.unitRect(CellRange(column: 0, row: 0, columnSpan: 1, rowSpan: 2)) == CGRect(x: 0, y: 0, width: 0.25, height: 1))
        #expect(layout.unitRect(CellRange(column: 1, row: 0, columnSpan: 2, rowSpan: 1)) == CGRect(x: 0.25, y: 0, width: 0.75, height: 0.5))
        #expect(layout.unitRect(CellRange(column: 2, row: 1)) == CGRect(x: 0.75, y: 0.5, width: 0.25, height: 0.5))
    }

    @Test func shrinkingClipsAndDropsZones() {
        let smaller = layout.resized(columns: 2, rows: 2)
        #expect(smaller.columns.count == 2)
        #expect(abs(smaller.columns[0] - 1.0 / 3) < 1e-9)
        #expect(abs(smaller.columns[1] - 2.0 / 3) < 1e-9)
        #expect(smaller.zones.map(\.name) == ["Left", "Right Top"])
        #expect(smaller.zones[1].cells.columnSpan == 1)

        let oneRow = layout.resized(columns: 3, rows: 1)
        #expect(oneRow.rows == [1])
        #expect(oneRow.zones.map(\.name) == ["Left", "Right Top"])
        #expect(oneRow.zones[0].cells.rowSpan == 1)
    }

    @Test func growingKeepsProportionsAndSumsToOne() {
        let bigger = layout.resized(columns: 4, rows: 2)
        #expect(bigger.columns.count == 4)
        #expect(abs(bigger.columns.reduce(0, +) - 1) < 1e-9)
        #expect(abs(bigger.columns[3] - 0.25) < 1e-9)
        #expect(abs(bigger.columns[1] / bigger.columns[0] - 2) < 1e-9)
        #expect(bigger.zones.count == 3)
    }

    @Test func shrinkingToZeroKeepsOneTrack() {
        let minimal = layout.resized(columns: 0, rows: 0)
        #expect(minimal.columns == [1])
        #expect(minimal.rows == [1])
        #expect(minimal.zones.map(\.name) == ["Left"])
    }

    @Test func nextZoneNameFillsGaps() {
        var named = ZoneLayout.default
        #expect(named.nextZoneName() == "Zone 1")
        named.zones = [Zone(name: "Zone 1", cells: CellRange(column: 0, row: 0)), Zone(name: "Zone 3", cells: CellRange(column: 1, row: 0))]
        #expect(named.nextZoneName() == "Zone 2")
    }

    @Test func hitTesting() {
        #expect(layout.zone(atUnit: CGPoint(x: 0.1, y: 0.9))?.name == "Left")
        #expect(layout.zone(atUnit: CGPoint(x: 0.5, y: 0.25))?.name == "Right Top")
        #expect(layout.zone(atUnit: CGPoint(x: 0.5, y: 0.75)) == nil)
        #expect(layout.cell(atUnit: CGPoint(x: 0.3, y: 0.6)) == (1, 1))
        #expect(layout.cell(atUnit: CGPoint(x: 1, y: 1)) == (2, 1))
    }

    @Test func overlapChecks() {
        #expect(!layout.canAdd(CellRange(column: 1, row: 1, columnSpan: 2, rowSpan: 1)))
        #expect(layout.canAdd(CellRange(column: 1, row: 1)))
        #expect(!layout.canAdd(CellRange(column: 2, row: 1, columnSpan: 2, rowSpan: 1)))
        #expect(CellRange(from: (2, 1), to: (0, 0)) == CellRange(column: 0, row: 0, columnSpan: 3, rowSpan: 2))
    }

    @Test func spanningZones() {
        let ids = layout.zones.map(\.id)
        #expect(layout.span([]) == nil)
        #expect(layout.span([ids[1]]) == layout.zones[1].cells)
        // Left + Corner: the bounding box is the whole grid.
        #expect(layout.span([ids[0], ids[2]]) == CellRange(column: 0, row: 0, columnSpan: 3, rowSpan: 2))
        #expect(layout.span([ids[1], ids[2]]) == CellRange(column: 1, row: 0, columnSpan: 2, rowSpan: 2))
    }

    @Test func layoutsRoundTripThroughJSON() throws {
        var withShortcut = layout
        withShortcut.zones[0].shortcut = Shortcut(keyCode: 18, modifiers: Shortcut.control | Shortcut.option)
        let data = try JSONEncoder().encode(["display": withShortcut])
        #expect(try JSONDecoder().decode([String: ZoneLayout].self, from: data)["display"] == withShortcut)
    }
}

import AppKit
import Testing
@testable import Strata

struct CoordinateTests {
    @Test func cocoaToAXFlipsAroundThePrimaryDisplay() {
        let cocoa = CGRect(x: 10, y: 100, width: 300, height: 200)
        #expect(ScreenGeometry.axRect(fromCocoa: cocoa, primaryHeight: 1000) == CGRect(x: 10, y: 700, width: 300, height: 200))
    }

    @Test(arguments: [
        CGRect(x: 10, y: 100, width: 300, height: 200),
        CGRect(x: -1920, y: 200, width: 800, height: 600), // display to the left
        CGRect(x: 0, y: 1000, width: 100, height: 100),    // display above the primary
    ])
    func roundTrip(rect: CGRect) {
        let ax = ScreenGeometry.axRect(fromCocoa: rect, primaryHeight: 1000)
        #expect(ScreenGeometry.cocoaRect(fromAX: ax, primaryHeight: 1000) == rect)
    }

    @Test func displayAboveThePrimaryHasNegativeAXY() {
        let above = CGRect(x: 0, y: 1000, width: 100, height: 100)
        #expect(ScreenGeometry.axRect(fromCocoa: above, primaryHeight: 1000).minY == -100)
    }
}

struct ShortcutTests {
    @Test func displayStrings() {
        #expect(SnapAction.leftHalf.defaultShortcut.displayString == "⌃⌥←")
        #expect(SnapAction.nextDisplay.defaultShortcut.displayString == "⌃⌥⌘→")
        #expect(SnapAction.maximize.defaultShortcut.displayString == "⌃⌥↩")
        #expect(SnapAction.restore.defaultShortcut.displayString == "⌃⌥⌫")
        let all = Shortcut(keyCode: KeyCode.space, modifiers: Shortcut.command | Shortcut.shift | Shortcut.option | Shortcut.control)
        #expect(all.displayString == "⌃⌥⇧⌘Space")
    }

    @Test func codableRoundTrip() throws {
        let shortcut = Shortcut(keyCode: KeyCode.k, modifiers: Shortcut.control | Shortcut.command)
        let decoded = try JSONDecoder().decode(Shortcut.self, from: JSONEncoder().encode(shortcut))
        #expect(decoded == shortcut)
    }

    @Test func recordingRequiresACommandControlOrOptionModifier() {
        func event(_ flags: NSEvent.ModifierFlags) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                             context: nil, characters: "k", charactersIgnoringModifiers: "k", isARepeat: false, keyCode: 40)!
        }
        #expect(Shortcut(event: event([])) == nil)
        #expect(Shortcut(event: event(.shift)) == nil)
        #expect(Shortcut(event: event([.control, .shift])) == Shortcut(keyCode: 40, modifiers: Shortcut.control | Shortcut.shift))
        #expect(Shortcut(event: event(.command)) == Shortcut(keyCode: 40, modifiers: Shortcut.command))
    }
}

struct GroupingTests {
    @Test func groupsSitWhereEachKeysFirstItemSits() {
        let items = ["a1", "b1", "a2", "c1", "b2", "a3"]
        #expect(items.groupedByFirstAppearance { $0.prefix(1) } == ["a1", "a2", "a3", "b1", "b2", "c1"])
    }

    @Test func groupingIsStableAndHandlesEmpty() {
        #expect([String]().groupedByFirstAppearance { $0 } == [])
        #expect(["x", "y", "z"].groupedByFirstAppearance { $0 } == ["x", "y", "z"])
    }
}

struct AppSearchTests {
    @Test func matchesIgnoringCaseAndDiacritics() {
        #expect(AppList.matches("Google Chrome", query: "chr"))
        #expect(AppList.matches("FaceTime", query: "facé"))
        #expect(AppList.matches("Calculator", query: "  "))
        #expect(!AppList.matches("Calculator", query: "xyz"))
    }
}

struct PinnedAppTests {
    @Test func insertingPinsBeforeASlotOrAtTheEnd() {
        let pins = ["a", "b", "c"]
        #expect(Settings.inserting(["x"], into: pins, at: 1) == ["a", "x", "b", "c"])
        #expect(Settings.inserting(["x", "y", "x"], into: pins, at: nil) == ["a", "b", "c", "x", "y"])
        #expect(Settings.inserting(["c"], into: pins, at: 0) == ["c", "a", "b"])
        #expect(Settings.inserting(["b"], into: pins, at: 1) == pins) // dropped on its own slot
        #expect(Settings.inserting(["a"], into: pins, at: 2) == ["b", "a", "c"])
    }

    @Test func numberShortcutLaunchesFocusesCyclesOrMinimizes() {
        #expect(WindowActions.pinnedStep(windows: [], focused: 5) == .launch)
        #expect(WindowActions.pinnedStep(windows: [1, 2], focused: 9) == .focus(1))
        #expect(WindowActions.pinnedStep(windows: [1, 2], focused: nil) == .focus(1))
        #expect(WindowActions.pinnedStep(windows: [1, 2, 3], focused: 2) == .focus(3))
        #expect(WindowActions.pinnedStep(windows: [1, 2, 3], focused: 3) == .focus(1))
        #expect(WindowActions.pinnedStep(windows: [7], focused: 7) == .minimize(7))
    }
}

import AppKit

/// What the bar can do to a window or app (spec §3.2).
enum WindowActions {
    static func focus(_ ref: WindowRef) {
        let running = NSRunningApplication(processIdentifier: ref.pid)
        if running?.isHidden == true { running?.unhide() }
        if AX.bool(ref.element, kAXMinimizedAttribute) == true {
            AX.set(ref.element, kAXMinimizedAttribute, kCFBooleanFalse)
        }
        AX.set(ref.element, kAXMainAttribute, kCFBooleanTrue)
        AX.perform(ref.element, kAXRaiseAction)
        // A background app can't activate others reliably via NSRunningApplication, but AX can.
        AX.set(AX.app(ref.pid), kAXFrontmostAttribute, kCFBooleanTrue)
        running?.activate()
        WindowTracker.shared.scheduleRefresh()
    }

    static func minimize(_ ref: WindowRef) {
        AX.set(ref.element, kAXMinimizedAttribute, kCFBooleanTrue)
        WindowTracker.shared.scheduleRefresh()
    }

    static func close(_ ref: WindowRef) {
        guard let button = AX.element(ref.element, kAXCloseButtonAttribute) else { return }
        AX.perform(button, kAXPressAction)
        WindowTracker.shared.scheduleRefresh()
    }

    /// Focus the window, or minimise it if it's already the focused one.
    static func toggle(_ window: TrackedWindow, focusedID: CGWindowID?) {
        if window.id == focusedID, !window.isMinimized, !window.isAppHidden {
            minimize(window.ref)
        } else {
            focus(window.ref)
        }
    }
}

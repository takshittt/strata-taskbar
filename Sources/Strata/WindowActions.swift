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

    /// An accessory app has to activate itself before its windows take keyboard focus. Cooperative
    /// activation can refuse `NSApp.activate()`, so fall back to the same AX route used for other apps.
    static func activateSelf() {
        NSApp.activate()
        if !NSApp.isActive {
            AX.set(AX.app(getpid()), kAXFrontmostAttribute, kCFBooleanTrue)
        }
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

// MARK: Apps

extension WindowActions {
    static func runningApp(_ bundleID: String) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
    }

    /// Launches the app, or asks a running one to reopen (which usually brings back a window).
    static func launch(bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            Log.error("no app found for \(bundleID)")
            return
        }
        launch(url: url)
    }

    static func launch(url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error { Log.error("launch \(url.lastPathComponent) failed: \(error.localizedDescription)") }
        }
    }

    enum PinnedStep: Equatable {
        case launch, focus(CGWindowID), minimize(CGWindowID)
    }

    /// What ⌃⌥<n> does, as ⊞<n> does on Windows: launch an app with no windows, focus its first window,
    /// step to the next one if one is already focused, or minimise it if it's the only one.
    static func pinnedStep(windows: [CGWindowID], focused: CGWindowID?) -> PinnedStep {
        guard let first = windows.first else { return .launch }
        guard let focused, let index = windows.firstIndex(of: focused) else { return .focus(first) }
        if windows.count == 1 { return .minimize(focused) }
        return .focus(windows[(index + 1) % windows.count])
    }

    /// Runs ⌃⌥<number> for the nth pinned app, counting from 1.
    static func activatePinned(_ number: Int) {
        let pins = Settings.shared.pinnedBundleIDs
        guard pins.indices.contains(number - 1) else { return }
        let bundleID = pins[number - 1]
        let tracker = WindowTracker.shared
        let windows = tracker.windows.filter { $0.bundleID == bundleID }
        switch pinnedStep(windows: windows.map(\.id), focused: tracker.focusedID) {
        case .launch: launch(bundleID: bundleID)
        case .focus(let id): if let window = tracker.window(id) { focus(window.ref) }
        case .minimize(let id): if let window = tracker.window(id) { minimize(window.ref) }
        }
    }

    /// Opens files or folders in a given app, as dropping them on its Dock icon does.
    static func open(_ urls: [URL], with app: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: configuration) { _, error in
            if let error { Log.error("open in \(app.lastPathComponent) failed: \(error.localizedDescription)") }
        }
    }

    /// Presses the app's "New … Window" menu item, falling back to ⌘N.
    static func openNewWindow(bundleID: String) {
        guard let app = runningApp(bundleID) else {
            launch(bundleID: bundleID)
            return
        }
        let axApp = AX.app(app.processIdentifier)
        if let item = newWindowMenuItem(axApp) {
            AX.perform(item, kAXPressAction)
            AX.set(axApp, kAXFrontmostAttribute, kCFBooleanTrue)
        } else {
            AX.set(axApp, kAXFrontmostAttribute, kCFBooleanTrue)
            postKeystroke(keyCode: 45, flags: .maskCommand, to: app.processIdentifier) // kVK_ANSI_N
        }
        WindowTracker.shared.scheduleRefresh()
    }

    /// Looks through the first few top-level menus (app, File, Shell…) for "New Window" or "New <Something> Window".
    private static func newWindowMenuItem(_ axApp: AXUIElement) -> AXUIElement? {
        guard let menuBar = AX.element(axApp, kAXMenuBarAttribute) else { return nil }
        for barItem in AX.elements(menuBar, kAXChildrenAttribute).dropFirst().prefix(4) {
            for menu in AX.elements(barItem, kAXChildrenAttribute) {
                for item in AX.elements(menu, kAXChildrenAttribute) {
                    let title = AX.string(item, kAXTitleAttribute) ?? ""
                    guard title == "New Window" || (title.hasPrefix("New ") && title.hasSuffix(" Window")) else { continue }
                    // Terminal's "New Window" is a submenu of profiles: take the first (default) one.
                    if let submenu = AX.elements(item, kAXChildrenAttribute).first,
                       let first = AX.elements(submenu, kAXChildrenAttribute).first {
                        return first
                    }
                    return item
                }
            }
        }
        return nil
    }

    /// Posts a key press, to one process if `pid` is given, otherwise system-wide.
    static func postKeystroke(keyCode: CGKeyCode, flags: CGEventFlags, to pid: pid_t? = nil) {
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: down) else { continue }
            event.flags = flags
            if let pid { event.postToPid(pid) } else { event.post(tap: .cghidEventTap) }
        }
    }
}

// MARK: Apps without windows

// Private, but long-standing (yabai relies on them). Only `isRealWindow` and `currentSpaces` use these.
@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> Int32
@_silgen_name("CGSWindowIsOrderedIn")
private func CGSWindowIsOrderedIn(_ connection: Int32, _ windowID: CGWindowID, _ orderedIn: UnsafeMutablePointer<Bool>) -> Int32
@_silgen_name("CGSCopySpacesForWindows")
private func CGSCopySpacesForWindows(_ connection: Int32, _ mask: Int32, _ windowIDs: CFArray) -> Unmanaged<CFArray>?
@_silgen_name("CGSCopyManagedDisplaySpaces")
private func CGSCopyManagedDisplaySpaces(_ connection: Int32) -> Unmanaged<CFArray>?

extension WindowActions {
    /// Regular apps with no real window anywhere. Finder is never included.
    ///
    /// Many apps (Claude, WhatsApp, Chrome, …) keep their last window after it is closed, just ordered
    /// out, so it still shows up in the window list. A real window is one that is ordered in, or sits
    /// on a Space that isn't showing, or that AX lists (which covers minimised windows and hidden apps).
    static func appsWithoutWindows() -> [NSRunningApplication] {
        let connection = CGSMainConnectionID()
        let showing = currentSpaces(connection)
        var pidsWithWindows = Set<pid_t>()
        let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        for info in list where (info[kCGWindowLayer as String] as? Int) == 0 {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, !pidsWithWindows.contains(pid),
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds),
                  rect.width >= 60, rect.height >= 60,
                  isRealWindow(id, connection: connection, showing: showing) else { continue }
            pidsWithWindows.insert(pid)
        }
        let ownPID = getpid()
        return NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != ownPID
                && $0.bundleIdentifier != "com.apple.finder" && !pidsWithWindows.contains($0.processIdentifier)
                && !hasAXWindow($0.processIdentifier)
        }
    }

    private static func isRealWindow(_ id: CGWindowID, connection: Int32, showing: Set<Int>) -> Bool {
        var orderedIn = false
        if CGSWindowIsOrderedIn(connection, id, &orderedIn) == 0, orderedIn { return true }
        // Mask 7: current, other and fixed Spaces. A window on a Space that isn't showing is kept,
        // since it may simply be over there.
        let spaces = CGSCopySpacesForWindows(connection, 7, [id] as CFArray)?.takeRetainedValue() as? [Int] ?? []
        return spaces.contains { !showing.contains($0) }
    }

    /// The Space showing on each display.
    private static func currentSpaces(_ connection: Int32) -> Set<Int> {
        let displays = CGSCopyManagedDisplaySpaces(connection)?.takeRetainedValue() as? [[String: Any]] ?? []
        return Set(displays.compactMap { ($0["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? Int })
    }

    private static func hasAXWindow(_ pid: pid_t) -> Bool {
        AX.elements(AX.app(pid), kAXWindowsAttribute).contains {
            let subrole = AX.string($0, kAXSubroleAttribute)
            return subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole
        }
    }

    static func quitAppsWithoutWindows() {
        for app in appsWithoutWindows() {
            Log.info("quitting \(app.localizedName ?? "?") (no windows)")
            app.terminate()
        }
    }

    static func quit(pid: pid_t) {
        NSRunningApplication(processIdentifier: pid)?.terminate()
    }
}

// MARK: Recent items

extension WindowActions {
    struct RecentItem {
        let title: String
        /// Set when the menu shows a path (VS Code and other Electron apps do), so the item can get a file icon.
        let path: String?
        let element: AXUIElement
    }

    /// The entries of the app's File ▸ Open Recent menu, read through AX. (The Dock's own per-app
    /// recents list lives in a file that needs Full Disk Access, which Strata doesn't ask for.)
    static func recentItems(pid: pid_t, limit: Int = 12) -> [RecentItem] {
        guard let menuBar = AX.element(AX.app(pid), kAXMenuBarAttribute) else { return [] }
        for barItem in AX.elements(menuBar, kAXChildrenAttribute).dropFirst().prefix(4) {
            for menu in AX.elements(barItem, kAXChildrenAttribute) {
                for item in AX.elements(menu, kAXChildrenAttribute) {
                    guard AX.string(item, kAXTitleAttribute)?.hasPrefix("Open Recent") == true,
                          let submenu = AX.elements(item, kAXChildrenAttribute).first else { continue }
                    return Array(AX.elements(submenu, kAXChildrenAttribute).compactMap(recentItem).prefix(limit))
                }
            }
        }
        return []
    }

    private static func recentItem(_ element: AXUIElement) -> RecentItem? {
        guard let title = AX.string(element, kAXTitleAttribute), !title.isEmpty,
              AX.bool(element, kAXEnabledAttribute) != false,
              !["Clear", "More", "Reopen"].contains(where: { title.hasPrefix($0) }) else { return nil }
        guard title.hasPrefix("/") || title.hasPrefix("~/") else {
            return RecentItem(title: title, path: nil, element: element)
        }
        let path = (title as NSString).expandingTildeInPath
        return RecentItem(title: (path as NSString).lastPathComponent, path: path, element: element)
    }

    static func open(_ recent: RecentItem, pid: pid_t) {
        AX.perform(recent.element, kAXPressAction)
        AX.set(AX.app(pid), kAXFrontmostAttribute, kCFBooleanTrue)
        WindowTracker.shared.scheduleRefresh()
    }
}

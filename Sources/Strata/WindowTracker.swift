import AppKit
import Combine

/// A live handle on another app's window. Identity is the `CGWindowID`.
struct WindowRef: Equatable {
    let id: CGWindowID
    let pid: pid_t
    let element: AXUIElement

    static func == (a: WindowRef, b: WindowRef) -> Bool { a.id == b.id }

    /// The frontmost app's focused window.
    static func focused() -> WindowRef? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = app.processIdentifier
        guard let element = AX.element(AX.app(pid), kAXFocusedWindowAttribute),
              let id = AX.windowID(element) else { return nil }
        return WindowRef(id: id, pid: pid, element: element)
    }

    var frame: CGRect? { AX.frame(element) }
}

struct TrackedWindow: Equatable {
    let ref: WindowRef
    let bundleID: String?
    let appName: String
    var title: String
    var isMinimized: Bool
    var isAppHidden: Bool
    var isFullScreen: Bool
    /// AX coordinates.
    var frame: CGRect

    var id: CGWindowID { ref.id }
    var pid: pid_t { ref.pid }
}

/// Keeps a live, ordered list of the user's windows on the current Space (spec §3.1).
final class WindowTracker {
    static let shared = WindowTracker()

    private(set) var windows: [TrackedWindow] = []
    private(set) var focusedID: CGWindowID?
    /// Fires when `windows` or `focusedID` changes.
    let didChange = PassthroughSubject<Void, Never>()
    /// Fires with the window's ID when a window is created, moved or resized.
    let geometryChanged = PassthroughSubject<CGWindowID, Never>()

    /// User-visible order. New windows go to the end.
    private var order: [CGWindowID] = []
    private var observers: [pid_t: AppObservation] = [:]
    /// When each previously listed window was first missed, for the brief gap during minimise animations.
    private var missingSince: [CGWindowID: CFAbsoluteTime] = [:]
    private static let missingGrace: CFAbsoluteTime = 1
    /// Off-screen windows already searched for by `offSpaceFullScreenWindows`.
    private var probed = Set<CGWindowID>()
    private var refreshPending = false
    private var pollTimer: Timer?

    private final class AppObservation {
        let observer: AXObserver
        let app: AXUIElement
        var appRegistered = false
        var windowIDs = Set<CGWindowID>()
        init(observer: AXObserver, app: AXUIElement) {
            self.observer = observer
            self.app = app
        }
    }

    private static let appNotifications = [
        kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification,
        kAXApplicationHiddenNotification, kAXApplicationShownNotification,
    ]
    private static let windowNotifications = [
        kAXUIElementDestroyedNotification, kAXTitleChangedNotification, kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification, kAXWindowMovedNotification, kAXWindowResizedNotification,
    ]

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification, NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
        ]
        for name in names {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                if name == NSWorkspace.didTerminateApplicationNotification,
                   let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                    self?.stopObserving(app.processIdentifier)
                }
                self?.scheduleRefresh()
            }
        }
        // Windows settle after the Space switch animation, so look again a little later.
        center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.scheduleRefresh()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self?.scheduleRefresh() }
        }
        // Safety net: some apps (notably Electron) fire AX notifications inconsistently.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.scheduleRefresh()
        }
        refresh()
    }

    /// Coalesces bursts of events into one re-scan 50 ms later.
    func scheduleRefresh() {
        guard !refreshPending else { return }
        refreshPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.refreshPending = false
            self?.refresh()
        }
    }

    func window(_ id: CGWindowID) -> TrackedWindow? {
        windows.first { $0.id == id }
    }

    /// Moves `ids` into the given order within the slots they already occupy, leaving other windows in place.
    func applyOrder(_ ids: [CGWindowID]) {
        let slots = ids.compactMap { order.firstIndex(of: $0) }.sorted()
        guard slots.count == ids.count else { return }
        for (slot, id) in zip(slots, ids) { order[slot] = id }
        windows.sort { (order.firstIndex(of: $0.id) ?? .max) < (order.firstIndex(of: $1.id) ?? .max) }
        didChange.send()
    }

    // MARK: Scanning

    func refresh() {
        let started = CFAbsoluteTimeGetCurrent()
        let onScreen = Self.onScreenWindowIDs()
        let ownPID = getpid()
        var found: [TrackedWindow] = []

        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && app.processIdentifier != ownPID {
            let pid = app.processIdentifier
            let axApp = AX.app(pid)
            let observation = observe(app: axApp, pid: pid)
            let hidden = app.isHidden

            for element in AX.elements(axApp, kAXWindowsAttribute) {
                guard let id = AX.windowID(element) else { continue }
                let subrole = AX.string(element, kAXSubroleAttribute)
                guard subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole else { continue }
                let minimized = AX.bool(element, kAXMinimizedAttribute) ?? false
                let fullScreen = AX.bool(element, "AXFullScreen") ?? false
                // Windows on other Spaces aren't on screen; minimised windows and hidden apps never are.
                // A full-screen window has a Space of its own and stays listed, as on Windows.
                guard onScreen.contains(id) || minimized || hidden || fullScreen else { continue }

                if let observation, !observation.windowIDs.contains(id) {
                    observe(window: element, id: id, in: observation)
                }
                found.append(TrackedWindow(
                    ref: WindowRef(id: id, pid: pid, element: element),
                    bundleID: app.bundleIdentifier,
                    appName: app.localizedName ?? "",
                    title: AX.string(element, kAXTitleAttribute) ?? "",
                    isMinimized: minimized,
                    isAppHidden: hidden,
                    isFullScreen: fullScreen,
                    frame: AX.frame(element) ?? .zero
                ))
            }
        }

        // During a minimise animation a window can vanish from AX and the screen for a moment.
        // Keep a still-existing window for a short grace period so its button doesn't flicker.
        let all = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        let alive = Self.windowIDs(all as CFArray)
        var ids = Set(found.map(\.id))
        probed.formIntersection(alive)
        found += offSpaceFullScreenWindows(all, onScreen: onScreen, known: ids)
        ids = Set(found.map(\.id))
        // AX usually leaves a full-screen window out of its app's windows while another Space is showing.
        // Keep a known one as long as it exists and still says it's full screen.
        for old in windows where !ids.contains(old.id) && alive.contains(old.id)
            && AX.bool(old.ref.element, "AXFullScreen") == true {
            var window = old
            window.title = AX.string(old.ref.element, kAXTitleAttribute) ?? old.title
            window.isFullScreen = true
            found.append(window)
            ids.insert(window.id)
        }
        for id in ids { missingSince[id] = nil }
        for old in windows where !ids.contains(old.id) && alive.contains(old.id) && inGracePeriod(old.id, now: started) {
            found.append(old)
            ids.insert(old.id)
        }
        missingSince = missingSince.filter { started - $0.value < Self.missingGrace }

        // Forget gone windows so a reused ID gets re-observed (re-adding a live one is a harmless no-op).
        for observation in observers.values { observation.windowIDs.formIntersection(ids) }
        // Windows that still exist (another Space, mid-animation) keep their place for when they return.
        order.removeAll { !ids.contains($0) && !alive.contains($0) }
        for window in found where !order.contains(window.id) { order.append(window.id) }
        found.sort { (order.firstIndex(of: $0.id) ?? .max) < (order.firstIndex(of: $1.id) ?? .max) }

        let focused = WindowRef.focused()?.id
        guard found != windows || focused != focusedID else { return }
        windows = found
        focusedID = focused
        let ms = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
        Log.info("windows (\(found.count), \(ms) ms, focused \(focused.map(String.init) ?? "none")): "
            + found.map { "\($0.id) \($0.appName) \"\($0.title)\"\($0.isMinimized ? " [min]" : "")" }.joined(separator: " | "))
        didChange.send()
    }

    /// Full-screen windows that were already on another Space when the app launched or Strata started.
    /// Each candidate is looked up once; after that it is a known window and kept above.
    private func offSpaceFullScreenWindows(_ all: [[String: Any]], onScreen: Set<CGWindowID>, known: Set<CGWindowID>) -> [TrackedWindow] {
        // Full screen fills the display's width, and its height less the notch strip on displays that have one.
        let screens = NSScreen.screens.map(\.frame.size)
        func fillsScreen(_ size: CGSize) -> Bool {
            screens.contains { $0.width == size.width && size.height <= $0.height && size.height >= $0.height - 80 }
        }
        var candidates: [pid_t: Set<CGWindowID>] = [:]
        for info in all where (info[kCGWindowLayer as String] as? Int) == 0 {
            guard let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  !onScreen.contains(id), !known.contains(id), !windows.contains(where: { $0.id == id }),
                  !probed.contains(id),
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo),
                  fillsScreen(bounds.size) else { continue }
            probed.insert(id)
            candidates[pid, default: []].insert(id)
        }
        var result: [TrackedWindow] = []
        for (pid, ids) in candidates {
            guard let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular,
                  pid != getpid() else { continue }
            for (id, element) in AX.offSpaceWindows(pid: pid, ids: ids)
            where AX.bool(element, "AXFullScreen") == true && AX.string(element, kAXSubroleAttribute) == kAXStandardWindowSubrole {
                result.append(TrackedWindow(
                    ref: WindowRef(id: id, pid: pid, element: element),
                    bundleID: app.bundleIdentifier,
                    appName: app.localizedName ?? "",
                    title: AX.string(element, kAXTitleAttribute) ?? "",
                    isMinimized: false,
                    isAppHidden: app.isHidden,
                    isFullScreen: true,
                    frame: AX.frame(element) ?? .zero
                ))
            }
        }
        return result
    }

    private func inGracePeriod(_ id: CGWindowID, now: CFAbsoluteTime) -> Bool {
        guard let since = missingSince[id] else {
            // First miss: keep it, and look again once the grace period is over.
            missingSince[id] = now
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.missingGrace + 0.05) { [weak self] in self?.scheduleRefresh() }
            return true
        }
        return now - since < Self.missingGrace
    }

    /// Layer-0 window IDs on screen right now. Reads only number and layer: no Screen Recording needed.
    private static func onScreenWindowIDs() -> Set<CGWindowID> {
        windowIDs(CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID))
    }

    private static func windowIDs(_ info: CFArray?) -> Set<CGWindowID> {
        guard let list = info as? [[String: Any]] else { return [] }
        var ids = Set<CGWindowID>()
        for info in list where (info[kCGWindowLayer as String] as? Int) == 0 {
            if let number = info[kCGWindowNumber as String] as? CGWindowID { ids.insert(number) }
        }
        return ids
    }

    // MARK: AX observers

    /// Returns the app's observation, creating it (or retrying registration) as needed.
    @discardableResult
    private func observe(app: AXUIElement, pid: pid_t) -> AppObservation? {
        let observation: AppObservation
        if let existing = observers[pid] {
            observation = existing
        } else {
            var observer: AXObserver?
            guard AXObserverCreate(pid, axCallback, &observer) == .success, let observer else { return nil }
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
            observation = AppObservation(observer: observer, app: app)
            observers[pid] = observation
        }
        if !observation.appRegistered {
            // A just-launched app may refuse at first; the next scan retries.
            let refcon = Unmanaged.passUnretained(self).toOpaque()
            let results = Self.appNotifications.map {
                AXObserverAddNotification(observation.observer, app, $0 as CFString, refcon)
            }
            observation.appRegistered = results.allSatisfy { $0 == .success || $0 == .notificationAlreadyRegistered }
        }
        return observation
    }

    private func observe(window: AXUIElement, id: CGWindowID, in observation: AppObservation) {
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in Self.windowNotifications {
            AXObserverAddNotification(observation.observer, window, name as CFString, refcon)
        }
        observation.windowIDs.insert(id)
    }

    private func stopObserving(_ pid: pid_t) {
        guard let observation = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observation.observer), .defaultMode)
    }

    fileprivate func handle(_ notification: String, element: AXUIElement) {
        switch notification {
        case kAXWindowMovedNotification, kAXWindowResizedNotification, kAXWindowCreatedNotification:
            if let id = AX.windowID(element) { geometryChanged.send(id) }
        default:
            break
        }
        scheduleRefresh()
    }
}

private func axCallback(_ observer: AXObserver, _ element: AXUIElement, _ notification: CFString, _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let tracker = Unmanaged<WindowTracker>.fromOpaque(refcon).takeUnretainedValue()
    tracker.handle(notification as String, element: element)
}

extension Array {
    /// Stable grouping: each key's items sit together, placed where that key's first item sits.
    func groupedByFirstAppearance<Key: Hashable>(by key: (Element) -> Key) -> [Element] {
        var groups: [Key: [Element]] = [:]
        var keys: [Key] = []
        for item in self {
            let k = key(item)
            if groups[k] == nil { keys.append(k) }
            groups[k, default: []].append(item)
        }
        return keys.flatMap { groups[$0]! }
    }
}

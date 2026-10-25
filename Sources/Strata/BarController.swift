import AppKit
import Combine

/// The bar's window: never key, never activates Strata, stays on every Space.
final class BarPanel: NSPanel {
    let content = BarContentView()

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isMovable = false
        isOpaque = false
        hasShadow = false
        backgroundColor = .clear
        // The blur is composited by the window server, so our pixels are transparent; without this,
        // clicks on the bar fall through to the window underneath.
        ignoresMouseEvents = false
        contentView = content
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Owns one `BarPanel` per display and keeps them in sync with settings and screens.
final class BarController {
    static let shared = BarController()

    private var panels: [CGDirectDisplayID: BarPanel] = [:]
    private var cancellables = Set<AnyCancellable>()

    var barHeight: CGFloat { CGFloat(Settings.shared.barHeight) }

    func start() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.rebuild()
        }
        Settings.shared.changed
            .debounce(for: .milliseconds(30), scheduler: RunLoop.main)
            .sink { [weak self] in self?.rebuild() }
            .store(in: &cancellables)
        // Launches and quits without window changes still change the pinned "running" dots.
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                if name == NSWorkspace.didTerminateApplicationNotification,
                   let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                    AppIcons.forget(pid: app.processIdentifier)
                }
                self?.updateContents()
            }
        }
        WindowTracker.shared.didChange
            .sink { [weak self] in self?.updateContents() }
            .store(in: &cancellables)
        rebuild()
    }

    /// Screens that should carry a bar under the current `barScope`.
    private var barScreens: [NSScreen] {
        let screens = NSScreen.screens
        return Settings.shared.barScope == .mainOnly ? Array(screens.prefix(1)) : screens
    }

    /// Creates, re-frames or removes panels so there is exactly one per bar screen.
    func rebuild() {
        let settings = Settings.shared
        Log.info("rebuilding bars for \(NSScreen.screens.count) screen(s)")
        var live: [CGDirectDisplayID: BarPanel] = [:]
        for screen in barScreens {
            guard let id = ScreenGeometry.displayID(screen) else { continue }
            let panel = panels[id] ?? BarPanel()
            panel.appearance = settings.appearance.nsAppearance
            panel.setFrame(barFrame(on: screen), display: true)
            panel.content.applySettings(settings)
            panel.orderFrontRegardless()
            live[id] = panel
        }
        for (id, panel) in panels where live[id] == nil {
            panel.orderOut(nil)
            panel.close()
        }
        panels = live
        updateContents()
        OverlapGuard.shared.checkAll()
    }

    /// Pushes the tracker's windows to every bar, filtered by hidden apps and display.
    func updateContents() {
        let settings = Settings.shared
        let tracker = WindowTracker.shared
        let hidden = Set(settings.hiddenBundleIDs)
        var windows = tracker.windows.filter { !hidden.contains($0.bundleID ?? "") }
        if settings.groupByApp { windows = windows.groupedByFirstAppearance { $0.pid } }

        // NSScreen objects can be recreated on configuration changes, so match displays by ID.
        var displayOf: [CGWindowID: CGDirectDisplayID] = [:]
        if settings.windowScope == .thisDisplay {
            for window in windows {
                displayOf[window.id] = ScreenGeometry.screen(for: window.frame).flatMap(ScreenGeometry.displayID)
            }
        }
        // Running apps with no windows at all (closed, not quit) keep an icon, as on Windows. Finder always runs.
        let withWindows = Set(tracker.windows.map(\.pid))
        let ownPID = getpid()
        var running: [String] = []
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && app.processIdentifier != ownPID && !withWindows.contains(app.processIdentifier) {
            guard let bundleID = app.bundleIdentifier, bundleID != "com.apple.finder", !hidden.contains(bundleID),
                  !running.contains(bundleID) else { continue }
            running.append(bundleID)
        }
        for (id, panel) in panels {
            let shown = settings.windowScope == .allDisplays ? windows : windows.filter { displayOf[$0.id] == id }
            panel.content.update(pinned: settings.pinnedBundleIDs, windows: shown, running: running,
                                 focusedID: tracker.focusedID, needsPermission: !Permission.shared.isTrusted)
        }
    }

    /// Bar frame in Cocoa coordinates: the bottom of the visible frame, so it sits above a bottom Dock.
    func barFrame(on screen: NSScreen) -> CGRect {
        let visible = screen.visibleFrame
        return CGRect(x: visible.minX, y: visible.minY, width: visible.width, height: barHeight)
    }

    var contentViews: [BarContentView] { panels.values.map(\.content) }

    func hasBar(on screen: NSScreen) -> Bool {
        guard let id = ScreenGeometry.displayID(screen) else { return false }
        return panels[id] != nil
    }
}

/// Keeps windows from sliding under the bar (spec §3.6): after a window moves or resizes, shrink it to
/// end at the bar's top edge, or move it up if it's too short to shrink.
final class OverlapGuard {
    static let shared = OverlapGuard()

    private static let debounce: TimeInterval = 0.3
    private static let minimumHeight: CGFloat = 120
    /// More adjustments than this to one window within `loopWindow` means the app is fighting back.
    private static let maxAdjustments = 3
    private static let loopWindow: CFAbsoluteTime = 5

    private var pending = Set<CGWindowID>()
    private var timer: Timer?
    private var adjustments: [CGWindowID: [CFAbsoluteTime]] = [:]
    private var cancellables = Set<AnyCancellable>()

    func start() {
        WindowTracker.shared.geometryChanged
            .sink { [weak self] id in self?.schedule([id]) }
            .store(in: &cancellables)
        Settings.shared.$avoidBarOverlap
            .removeDuplicates()
            .filter { $0 }
            .sink { [weak self] _ in DispatchQueue.main.async { self?.checkAll() } }
            .store(in: &cancellables)
    }

    func checkAll() {
        schedule(WindowTracker.shared.windows.map(\.id))
    }

    private func schedule(_ ids: [CGWindowID]) {
        guard Settings.shared.avoidBarOverlap else { return }
        pending.formUnion(ids)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.debounce, repeats: false) { [weak self] _ in self?.check() }
    }

    private func check() {
        // Never fight a drag the user is still doing: wait until the mouse is released.
        guard NSEvent.pressedMouseButtons == 0 else {
            schedule([])
            return
        }
        let ids = pending
        pending.removeAll()
        let now = CFAbsoluteTimeGetCurrent()
        for id in ids {
            guard let window = WindowTracker.shared.window(id),
                  !window.isMinimized, !window.isAppHidden,
                  AX.bool(window.ref.element, "AXFullScreen") != true,
                  let frame = AX.frame(window.ref.element),
                  let screen = ScreenGeometry.screen(for: frame),
                  BarController.shared.hasBar(on: screen) else { continue }

            let barTop = ScreenGeometry.axRect(fromCocoa: BarController.shared.barFrame(on: screen)).minY
            // Only windows that reach into the bar but start above it.
            guard frame.maxY > barTop + 1, frame.minY < barTop else { continue }

            let recent = (adjustments[id] ?? []).filter { now - $0 < Self.loopWindow }
            guard recent.count < Self.maxAdjustments else {
                Log.info("overlap guard: giving up on window \(id) (\(window.appName)) after repeated adjustments")
                continue
            }
            adjustments[id] = recent + [now]
            fit(window.ref, frame: frame, barTop: barTop, workTop: ScreenGeometry.axWorkArea(screen).minY)
        }
        adjustments = adjustments.filter { $0.value.contains { now - $0 < Self.loopWindow } }
    }

    private func fit(_ ref: WindowRef, frame: CGRect, barTop: CGFloat, workTop: CGFloat) {
        let available = barTop - frame.minY
        if available >= Self.minimumHeight {
            var size = CGSize(width: frame.width, height: available)
            if let value = AXValueCreate(.cgSize, &size) { AX.set(ref.element, kAXSizeAttribute, value) }
            Log.info("overlap guard: shrank window \(ref.id) to end at the bar")
        }
        // Too short to shrink, or the app kept its height: move it up instead.
        guard let now = AX.frame(ref.element), now.maxY > barTop + 1 else { return }
        var origin = CGPoint(x: now.minX, y: max(workTop, barTop - now.height))
        if let value = AXValueCreate(.cgPoint, &origin) { AX.set(ref.element, kAXPositionAttribute, value) }
        Log.info("overlap guard: moved window \(ref.id) above the bar")
    }
}

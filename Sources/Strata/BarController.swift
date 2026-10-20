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
        for (id, panel) in panels {
            let shown = settings.windowScope == .allDisplays ? windows : windows.filter { displayOf[$0.id] == id }
            panel.content.update(pinned: settings.pinnedBundleIDs, windows: shown, focusedID: tracker.focusedID)
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

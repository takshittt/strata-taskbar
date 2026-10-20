import AppKit

/// App icons, cached by PID (running apps) and bundle ID (pinned apps).
enum AppIcons {
    private static var byPID: [pid_t: NSImage] = [:]
    private static var byBundleID: [String: NSImage] = [:]

    static func icon(pid: pid_t) -> NSImage? {
        if let cached = byPID[pid] { return cached }
        let icon = NSRunningApplication(processIdentifier: pid)?.icon
        byPID[pid] = icon
        return icon
    }

    static func forget(pid: pid_t) {
        byPID[pid] = nil
    }

    static func icon(bundleID: String) -> NSImage? {
        if let cached = byBundleID[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        byBundleID[bundleID] = icon
        return icon
    }
}

/// One button per window: icon, optional title, dimmed when minimised, underlined when focused.
final class WindowButton: BarItemView {
    private(set) var tracked: TrackedWindow
    private var focusedID: CGWindowID?

    init(window: TrackedWindow) {
        self.tracked = window
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func update(window: TrackedWindow, focusedID: CGWindowID?) {
        let changed = window != self.tracked || focusedID != self.focusedID
        self.tracked = window
        self.focusedID = focusedID
        isActive = window.id == focusedID
        if changed { needsDisplay = true }
    }

    override var tipText: String? {
        tracked.title.isEmpty ? tracked.appName : "\(tracked.appName) — \(tracked.title)"
    }

    override func primaryClick() {
        WindowActions.toggle(tracked, focusedID: focusedID)
    }

    override func middleClick() {
        WindowActions.close(tracked.ref)
    }

    override func contextMenu() -> NSMenu? {
        let window = tracked
        let settings = Settings.shared
        let menu = NSMenu.manual()
        let header = window.title.isEmpty ? window.appName : window.title
        menu.addHeader(header.count > 60 ? String(header.prefix(59)) + "…" : header)
        menu.addItem(.separator())

        if window.isMinimized {
            menu.addItem(MenuAction("Restore") { WindowActions.focus(window.ref) })
        } else {
            menu.addItem(MenuAction("Minimize") { WindowActions.minimize(window.ref) })
        }
        if let bundleID = window.bundleID {
            menu.addItem(MenuAction("New Window") { WindowActions.openNewWindow(bundleID: bundleID) })
        }
        menu.addItem(MenuAction("Close Window") { WindowActions.close(window.ref) })
        BarMenus.addWindowSubmenus(to: menu, window: window)

        if let bundleID = window.bundleID {
            menu.addItem(.separator())
            if settings.isPinned(bundleID) {
                menu.addItem(MenuAction("Unpin \(window.appName)") { settings.unpin(bundleID) })
            } else {
                menu.addItem(MenuAction("Pin \(window.appName)") { settings.pin(bundleID) })
            }
            menu.addItem(MenuAction("Hide \(window.appName) from Bar") { settings.hide(bundleID) })
        }
        menu.addItem(.separator())
        menu.addItem(MenuAction("Quit \(window.appName)") { WindowActions.quit(pid: window.pid) })
        return menu
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let alpha: CGFloat = tracked.isMinimized || tracked.isAppHidden ? 0.45 : 1
        let size = iconSize
        let settings = Settings.shared
        let showTitle = settings.showTitles && bounds.width >= size + 40
        let iconX = showTitle ? 8 : ((bounds.width - size) / 2).rounded()
        drawIcon(AppIcons.icon(pid: tracked.pid), x: iconX, size: size, alpha: alpha)

        if showTitle {
            let style = NSMutableParagraphStyle()
            style.lineBreakMode = .byTruncatingTail
            let font = NSFont.systemFont(ofSize: CGFloat(settings.fontSize))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.labelColor.withAlphaComponent(alpha),
                .paragraphStyle: style,
            ]
            let x = iconX + size + 6
            let height = ceil(font.ascender - font.descender)
            let rect = CGRect(x: x, y: ((bounds.height - height) / 2).rounded(), width: bounds.width - x - 6, height: height)
            (tracked.title.isEmpty ? tracked.appName : tracked.title).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes)
        }

        if isActive {
            NSColor.controlAccentColor.setFill()
            let width = min(bounds.width - 12, showTitle ? bounds.width - 12 : 16)
            NSBezierPath(roundedRect: CGRect(x: (bounds.width - width) / 2, y: 1, width: width, height: 2.5), xRadius: 1.25, yRadius: 1.25).fill()
        }
    }
}

/// The Start button: opens the apps menu, Spotlight or Raycast.
final class StartButton: BarItemView {
    override var isDraggable: Bool { false }
    override var tipText: String? { "Start" }

    override func primaryClick() {
        switch Settings.shared.startAction {
        case .appsMenu:
            showAppsMenu()
        case .spotlight:
            WindowActions.postKeystroke(keyCode: 49, flags: .maskCommand) // kVK_Space
        case .raycast:
            if NSWorkspace.shared.urlForApplication(withBundleIdentifier: AppList.raycastBundleID) != nil {
                WindowActions.postKeystroke(keyCode: 49, flags: .maskAlternate)
            } else {
                showAppsMenu()
            }
        }
    }

    private func showAppsMenu() {
        AppList.menu().popUp(positioning: nil, at: CGPoint(x: 0, y: bounds.height + 4), in: self)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let configuration = NSImage.SymbolConfiguration(pointSize: (bounds.height * 0.45).rounded(), weight: .semibold)
            .applying(.init(paletteColors: [.controlAccentColor]))
        guard let symbol = NSImage(systemSymbolName: "square.grid.2x2.fill", accessibilityDescription: "Start")?
            .withSymbolConfiguration(configuration) else { return }
        let size = symbol.size
        symbol.draw(in: CGRect(x: ((bounds.width - size.width) / 2).rounded(), y: ((bounds.height - size.height) / 2).rounded(),
                               width: size.width, height: size.height))
    }
}

/// A pinned app with no windows on this bar: click to launch (or focus its windows elsewhere).
final class PinnedButton: BarItemView {
    let bundleID: String

    init(bundleID: String) {
        self.bundleID = bundleID
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    var appName: String {
        if let app = WindowActions.runningApp(bundleID), let name = app.localizedName { return name }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    override var tipText: String? { appName }

    override func primaryClick() {
        // The app may have windows on another display's bar.
        if let window = WindowTracker.shared.windows.first(where: { $0.bundleID == bundleID }) {
            WindowActions.focus(window.ref)
        } else {
            WindowActions.launch(bundleID: bundleID)
        }
    }

    override func middleClick() {
        WindowActions.openNewWindow(bundleID: bundleID)
    }

    override func contextMenu() -> NSMenu? {
        let bundleID = bundleID
        let menu = NSMenu.manual()
        menu.addHeader(appName)
        menu.addItem(.separator())
        menu.addItem(MenuAction("New Window") { WindowActions.openNewWindow(bundleID: bundleID) })
        menu.addItem(MenuAction("Unpin") { Settings.shared.unpin(bundleID) })
        if let app = WindowActions.runningApp(bundleID) {
            menu.addItem(.separator())
            menu.addItem(MenuAction("Quit \(appName)") { app.terminate() })
        }
        return menu
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let size = iconSize
        drawIcon(AppIcons.icon(bundleID: bundleID), x: ((bounds.width - size) / 2).rounded(), size: size)
        if WindowActions.runningApp(bundleID) != nil {
            NSColor.secondaryLabelColor.setFill()
            NSBezierPath(ovalIn: CGRect(x: bounds.midX - 1.5, y: 1, width: 3, height: 3)).fill()
        }
    }
}

/// Shown instead of window buttons while Strata lacks Accessibility permission.
final class PermissionButton: BarItemView {
    override var isDraggable: Bool { false }
    override var tipText: String? { "Open Privacy & Security → Accessibility" }

    override func primaryClick() {
        AX.promptForTrust()
        Permission.openSystemSettings()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            .applying(.init(paletteColors: [.systemOrange]))
        let symbol = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        let size = symbol?.size ?? .zero
        symbol?.draw(in: CGRect(x: 8, y: ((bounds.height - size.height) / 2).rounded(), width: size.width, height: size.height))

        let font = NSFont.systemFont(ofSize: CGFloat(Settings.shared.fontSize), weight: .medium)
        let text = "Strata needs Accessibility access — click to grant"
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
        let height = ceil(font.ascender - font.descender)
        text.draw(with: CGRect(x: 14 + size.width, y: ((bounds.height - height) / 2).rounded(), width: bounds.width - size.width - 20, height: height),
                  options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes)
    }
}

/// Installed apps for the Start menu (spec §3.7).
enum AppList {
    static let raycastBundleID = "com.raycast.macos"

    private static let directories = [
        "/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
        NSString(string: "~/Applications").expandingTildeInPath,
    ]

    struct App {
        let name: String
        let url: URL
    }

    static func apps() -> [App] {
        let fm = FileManager.default
        var seen = Set<String>()
        var apps: [App] = []
        for directory in directories {
            guard let names = try? fm.contentsOfDirectory(atPath: directory) else { continue }
            for name in names where name.hasSuffix(".app") {
                let url = URL(fileURLWithPath: directory).appendingPathComponent(name)
                let display = fm.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
                guard seen.insert(display).inserted else { continue }
                apps.append(App(name: display, url: url))
            }
        }
        return apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// One item per app. NSMenu's built-in type-to-select acts as search.
    static func menu() -> NSMenu {
        let menu = NSMenu.manual("Apps")
        for app in apps() {
            let item = MenuAction(app.name) { WindowActions.launch(url: app.url) }
            let icon = NSWorkspace.shared.icon(forFile: app.url.path)
            icon.size = CGSize(width: 16, height: 16)
            item.image = icon
            menu.addItem(item)
        }
        return menu
    }
}

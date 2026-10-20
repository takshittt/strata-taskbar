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

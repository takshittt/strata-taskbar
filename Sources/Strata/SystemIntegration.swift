import AppKit
import Combine
import ServiceManagement

/// Launch at login via `SMAppService` (spec §3.8). Only works from the real, signed `.app` bundle.
final class LoginItem: ObservableObject {
    static let shared = LoginItem()

    @Published private(set) var isEnabled = SMAppService.mainApp.status == .enabled
    @Published private(set) var lastError: String?

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            Log.error("launch at login: \(error.localizedDescription)")
        }
        refresh()
    }

    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}

/// Moves the Dock off the bottom edge and turns on auto-hide, so it doesn't clash with the bar.
enum DockSetup {
    /// Asks first, since this changes a system setting and restarts the Dock.
    static func confirmAndApply() {
        WindowActions.activateSelf()
        let alert = NSAlert()
        alert.messageText = "Move the Dock to the left and hide it automatically?"
        alert.informativeText = "This changes your Dock settings and restarts the Dock. You can change them back in System Settings → Desktop & Dock."
        alert.addButton(withTitle: "Move & Auto-hide")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        moveAndAutoHide(to: "left")
    }

    static func moveAndAutoHide(to orientation: String) {
        run("/usr/bin/defaults", ["write", "com.apple.dock", "orientation", "-string", orientation])
        run("/usr/bin/defaults", ["write", "com.apple.dock", "autohide", "-bool", "true"])
        run("/usr/bin/killall", ["Dock"])
        Log.info("dock moved \(orientation) with auto-hide")
    }

    private static func run(_ path: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            Log.error("\(path) failed: \(error.localizedDescription)")
        }
    }
}

/// Live Accessibility status, polled so revoking it while running is noticed.
final class Permission: ObservableObject {
    static let shared = Permission()

    @Published private(set) var isTrusted = AX.isTrusted
    private var timer: Timer?
    #if DEBUG
    /// Lets the "revoked" state be checked without revoking the real grant.
    var simulateRevoked = false
    #endif

    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            var trusted = AX.isTrusted
            #if DEBUG
            if self.simulateRevoked { trusted = false }
            #endif
            if trusted != self.isTrusted {
                Log.info(trusted ? "accessibility granted" : "accessibility revoked")
                self.isTrusted = trusted
            }
        }
    }

    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}

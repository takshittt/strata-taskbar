import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var trustTimer: Timer?
    private var servicesStarted = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.info("launched (pid \(getpid()))")
        BarController.shared.start()

        if AX.isTrusted {
            startServices()
            return
        }

        Log.info("not trusted, prompting for Accessibility")
        AX.promptForTrust()
        // The grant takes effect in the running process, so poll instead of asking for a relaunch.
        trustTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, AX.isTrusted else { return }
                self.trustTimer?.invalidate()
                self.trustTimer = nil
                self.startServices()
            }
        }
    }

    private func startServices() {
        guard !servicesStarted else { return }
        servicesStarted = true
        Log.info("trusted, starting services")
        logFrontmostWindow()
    }

    /// Smoke check for the AX wrappers until WindowTracker exists (Phase 3).
    private func logFrontmostWindow() {
        guard let front = NSWorkspace.shared.frontmostApplication,
              let window = AX.element(AX.app(front.processIdentifier), kAXFocusedWindowAttribute) else {
            Log.info("no focused window to inspect")
            return
        }
        let frame = AX.frame(window) ?? .zero
        let screen = ScreenGeometry.screen(for: frame).flatMap(ScreenGeometry.displayKey) ?? "?"
        let title = AX.string(window, kAXTitleAttribute) ?? ""
        Log.info("focused window \(front.localizedName ?? "?") — \"\(title)\" id=\(AX.windowID(window) ?? 0) frame=\(frame) display=\(screen)")
    }
}

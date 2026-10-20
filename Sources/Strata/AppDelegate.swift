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
        WindowTracker.shared.start()
    }
}

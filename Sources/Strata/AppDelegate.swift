import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var servicesStarted = false
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.info("launched (pid \(getpid()))")
        installMainMenu()
        BarMenus.showSettings = { SettingsWindow.shared.show() }
        BarMenus.showZoneEditor = { ZoneEditorWindow.shared.show() }
        BarController.shared.start()
        #if DEBUG
        DebugSnapshot.install()
        #endif

        if !AX.isTrusted {
            Log.info("not trusted, prompting for Accessibility")
            AX.promptForTrust()
        }
        // The grant takes effect in the running process, so watch for it instead of asking for a relaunch.
        // Revoking it later shows a message on the bar until it's granted again.
        Permission.shared.startMonitoring()
        Permission.shared.$isTrusted
            .removeDuplicates()
            .sink { [weak self] trusted in
                DispatchQueue.main.async {
                    if trusted { self?.startServices() }
                    WindowTracker.shared.scheduleRefresh()
                    BarController.shared.updateContents()
                }
            }
            .store(in: &cancellables)
    }

    private func startServices() {
        guard !servicesStarted else { return }
        servicesStarted = true
        Log.info("trusted, starting services")
        WindowTracker.shared.start()

        BarMenus.windowSubmenus = { menu, window in
            menu.addItem(.separator())
            menu.addItem(WindowMover.snapMenuItem(for: window.ref))
            if let zones = WindowMover.zoneMenuItem(for: window.ref) { menu.addItem(zones) }
        }
        HotKeys.shared.zoneBindings = { ZoneStore.shared.shortcutBindings }
        HotKeys.shared.onTrigger = { target in
            switch target {
            case .snap(let action): WindowMover.perform(action)
            case .zone(let display, let zone): WindowMover.moveFocused(toZone: zone, display: display)
            }
        }
        HotKeys.shared.start()
        OverlapGuard.shared.start()
        OverlapGuard.shared.checkAll()
        ZoneGridOverlay.shared.start()
    }

    /// Never shown (the app is LSUIElement), but routes standard edit shortcuts in the Settings and Zone Editor windows.
    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Strata", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }
}

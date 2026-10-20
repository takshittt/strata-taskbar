import AppKit

// Apps we launch inherit our environment. Started from VS Code's terminal we carry ELECTRON_RUN_AS_NODE=1,
// which makes every Electron app (VS Code, Slack, …) run as headless Node and quit at once.
unsetenv("ELECTRON_RUN_AS_NODE")

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// No Dock icon and no menu bar (Info.plist also sets LSUIElement).
app.setActivationPolicy(.accessory)
app.run()

import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// No Dock icon and no menu bar (Info.plist also sets LSUIElement).
app.setActivationPolicy(.accessory)
app.run()

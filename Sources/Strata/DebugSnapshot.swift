#if DEBUG
import AppKit

/// Debug builds only: `postDebugSnapshot` (any process posting the distributed notification
/// "local.strata.debug.snapshot") makes each bar render itself to /tmp/strata-bar-<n>.png.
/// Lets bar layout be checked without Screen Recording permission.
/// "local.strata.debug.click" with object "<bar>:<item>[:middle]" runs that item's click handler,
/// so actions can be tested without moving the user's mouse. ":menu" logs the item's context menu instead.
enum DebugSnapshot {
    private static func describe(_ menu: NSMenu?) -> String {
        (menu?.items ?? []).map { item in
            if item.isSeparatorItem { return "—" }
            let sub = item.submenu.map { " ▸ [" + describe($0) + "]" } ?? ""
            return (item.isEnabled ? "" : "(off) ") + item.title + sub
        }.joined(separator: " | ")
    }

    static func install() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("local.strata.debug.click"), object: nil, queue: .main
        ) { note in
            let parts = (note.object as? String ?? "").split(separator: ":")
            let views = BarController.shared.contentViews
            guard parts.count >= 2, let b = Int(parts[0]), let i = Int(parts[1]), b < views.count else { return }
            let items = views[b].units.flatMap(\.items)
            guard items.indices.contains(i) else { return }
            Log.info("debug click on \(type(of: items[i])) \(items[i].tipText ?? "")")
            switch parts.count > 2 ? String(parts[2]) : "" {
            case "middle": items[i].middleClick()
            case "menu":
                let menu = items[i].contextMenu()
                if parts.count > 3, let n = Int(parts[3]), let item = menu?.items[safe: n] {
                    Log.info("performing menu item \(item.title)")
                    menu?.performActionForItem(at: n)
                } else {
                    Log.info("menu: " + describe(menu))
                }
            default: items[i].primaryClick()
            }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("local.strata.debug.snapshot"), object: nil, queue: .main
        ) { _ in
            for (index, view) in BarController.shared.contentViews.enumerated() {
                guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                let url = URL(fileURLWithPath: "/tmp/strata-bar-\(index).png")
                try? rep.representation(using: .png, properties: [:])?.write(to: url)
                Log.info("debug snapshot written to \(url.path)")
            }
        }
    }
}
private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
#endif

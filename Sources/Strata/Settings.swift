import AppKit
import Combine

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "Match System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    /// `nil` follows the system.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

enum BarAlignment: String, CaseIterable, Identifiable {
    case left, center
    var id: String { rawValue }
    var title: String { self == .left ? "Left" : "Center" }
}

enum BarScope: String, CaseIterable, Identifiable {
    case allDisplays, mainOnly
    var id: String { rawValue }
    var title: String { self == .allDisplays ? "All displays" : "Main display only" }
}

enum WindowScope: String, CaseIterable, Identifiable {
    case thisDisplay, allDisplays
    var id: String { rawValue }
    var title: String { self == .thisDisplay ? "Windows on this display" : "Windows on all displays" }
}

enum StartAction: String, CaseIterable, Identifiable {
    case appsMenu, spotlight, raycast
    var id: String { rawValue }
    var title: String {
        switch self {
        case .appsMenu: return "Apps menu"
        case .spotlight: return "Spotlight (⌘Space)"
        case .raycast: return "Raycast (⌥Space)"
        }
    }
}

/// Every user preference, backed by UserDefaults. `changed` fires after any write.
final class Settings: ObservableObject {
    static let shared = Settings()

    static let defaultPins = ["com.apple.finder", "com.apple.Safari", "com.apple.Terminal"]

    let changed = PassthroughSubject<Void, Never>()
    private let defaults = UserDefaults.standard

    @Published var alignment: BarAlignment { didSet { store("alignment", alignment.rawValue) } }
    @Published var appearance: Appearance { didSet { store("appearance", appearance.rawValue) } }
    @Published var barScope: BarScope { didSet { store("barScope", barScope.rawValue) } }
    @Published var windowScope: WindowScope { didSet { store("windowScope", windowScope.rawValue) } }
    @Published var startAction: StartAction { didSet { store("startAction", startAction.rawValue) } }
    @Published var barHeight: Double { didSet { store("barHeight", barHeight) } }
    @Published var fontSize: Double { didSet { store("fontSize", fontSize) } }
    @Published var opacity: Double { didSet { store("opacity", opacity) } }
    @Published var windowGap: Double { didSet { store("windowGap", windowGap) } }
    @Published var showTitles: Bool { didSet { store("showTitles", showTitles) } }
    @Published var groupByApp: Bool { didSet { store("groupByApp", groupByApp) } }
    @Published var avoidBarOverlap: Bool { didSet { store("avoidBarOverlap", avoidBarOverlap) } }
    @Published var hotKeysEnabled: Bool { didSet { store("hotKeysEnabled", hotKeysEnabled) } }
    @Published var pinnedBundleIDs: [String] { didSet { store("pinnedBundleIDs", pinnedBundleIDs) } }
    @Published var hiddenBundleIDs: [String] { didSet { store("hiddenBundleIDs", hiddenBundleIDs) } }

    private init() {
        let d = UserDefaults.standard
        func choice<E: RawRepresentable>(_ key: String, _ fallback: E) -> E where E.RawValue == String {
            d.string(forKey: key).flatMap(E.init(rawValue:)) ?? fallback
        }
        func value<T>(_ key: String, _ fallback: T) -> T { d.object(forKey: key) as? T ?? fallback }

        alignment = choice("alignment", .left)
        appearance = choice("appearance", .system)
        barScope = choice("barScope", .allDisplays)
        windowScope = choice("windowScope", .thisDisplay)
        startAction = choice("startAction", .appsMenu)
        barHeight = value("barHeight", 40)
        fontSize = value("fontSize", 12)
        opacity = value("opacity", 1)
        windowGap = value("windowGap", 0)
        showTitles = value("showTitles", true)
        groupByApp = value("groupByApp", true)
        avoidBarOverlap = value("avoidBarOverlap", true)
        hotKeysEnabled = value("hotKeysEnabled", true)
        pinnedBundleIDs = value("pinnedBundleIDs", Settings.defaultPins)
        hiddenBundleIDs = value("hiddenBundleIDs", [])
    }

    private func store(_ key: String, _ value: Any) {
        defaults.set(value, forKey: key)
        changed.send()
    }

    // MARK: Pinned and hidden apps

    func isPinned(_ bundleID: String) -> Bool { pinnedBundleIDs.contains(bundleID) }
    func isHidden(_ bundleID: String) -> Bool { hiddenBundleIDs.contains(bundleID) }

    func pin(_ bundleID: String) {
        guard !isPinned(bundleID) else { return }
        pinnedBundleIDs.append(bundleID)
    }

    func unpin(_ bundleID: String) {
        pinnedBundleIDs.removeAll { $0 == bundleID }
    }

    func hide(_ bundleID: String) {
        guard !isHidden(bundleID) else { return }
        hiddenBundleIDs.append(bundleID)
    }

    func unhide(_ bundleID: String) {
        hiddenBundleIDs.removeAll { $0 == bundleID }
    }
}

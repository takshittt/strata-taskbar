import AppKit
import Carbon
import Combine

/// Virtual key codes (Carbon `kVK_*`) used by the default shortcuts.
enum KeyCode {
    static let a: UInt32 = 0, d: UInt32 = 2, f: UInt32 = 3, g: UInt32 = 5, c: UInt32 = 8
    static let e: UInt32 = 14, t: UInt32 = 17, u: UInt32 = 32, i: UInt32 = 34, j: UInt32 = 38, k: UInt32 = 40
    static let returnKey: UInt32 = 36, tab: UInt32 = 48, space: UInt32 = 49, delete: UInt32 = 51, escape: UInt32 = 53
    static let forwardDelete: UInt32 = 117, home: UInt32 = 115, end: UInt32 = 119, pageUp: UInt32 = 116, pageDown: UInt32 = 121
    /// 1 through 9 on the main row.
    static let digits: [UInt32] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
    static let leftArrow: UInt32 = 123, rightArrow: UInt32 = 124, downArrow: UInt32 = 125, upArrow: UInt32 = 126
}

/// A key plus Carbon modifier flags, as registered with `RegisterEventHotKey`.
struct Shortcut: Codable, Hashable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let command = UInt32(cmdKey)
    static let shift = UInt32(shiftKey)
    static let option = UInt32(optionKey)
    static let control = UInt32(controlKey)

    /// From a recorded key-down. Requires ⌘, ⌃ or ⌥ so plain typing never becomes a global shortcut.
    init?(event: NSEvent) {
        let flags = event.modifierFlags
        var modifiers: UInt32 = 0
        if flags.contains(.control) { modifiers |= Self.control }
        if flags.contains(.option) { modifiers |= Self.option }
        if flags.contains(.shift) { modifiers |= Self.shift }
        if flags.contains(.command) { modifiers |= Self.command }
        guard modifiers & (Self.command | Self.control | Self.option) != 0 else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: modifiers)
    }

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// e.g. "⌃⌥←", in the standard macOS modifier order.
    var displayString: String {
        var result = ""
        if modifiers & Self.control != 0 { result += "⌃" }
        if modifiers & Self.option != 0 { result += "⌥" }
        if modifiers & Self.shift != 0 { result += "⇧" }
        if modifiers & Self.command != 0 { result += "⌘" }
        return result + Self.keyName(keyCode)
    }

    private static let specialKeyNames: [UInt32: String] = [
        KeyCode.leftArrow: "←", KeyCode.rightArrow: "→", KeyCode.upArrow: "↑", KeyCode.downArrow: "↓",
        KeyCode.returnKey: "↩", KeyCode.delete: "⌫", KeyCode.forwardDelete: "⌦", KeyCode.escape: "⎋",
        KeyCode.tab: "⇥", KeyCode.space: "Space", KeyCode.home: "↖", KeyCode.end: "↘",
        KeyCode.pageUp: "⇞", KeyCode.pageDown: "⇟",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    /// Special keys by symbol; everything else through the current keyboard layout, so labels match non-US layouts.
    static func keyName(_ keyCode: UInt32) -> String {
        if let name = specialKeyNames[keyCode] { return name }
        return translate(keyCode)?.uppercased() ?? "#\(keyCode)"
    }

    private static func translate(_ keyCode: UInt32) -> String? {
        for source in [TISCopyCurrentKeyboardLayoutInputSource(), TISCopyCurrentASCIICapableKeyboardLayoutInputSource()] {
            guard let source = source?.takeRetainedValue(),
                  let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { continue }
            let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
            var deadKeys: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var length = 0
            let status = data.withUnsafeBytes { raw -> OSStatus in
                guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return -1 }
                return UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                      OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars)
            }
            if status == noErr, length > 0 { return String(utf16CodeUnits: chars, count: length) }
        }
        return nil
    }

    /// Key equivalent for showing the shortcut next to a menu item.
    var menuKeyEquivalent: (String, NSEvent.ModifierFlags)? {
        let key: String
        switch keyCode {
        case KeyCode.leftArrow: key = String(UnicodeScalar(NSLeftArrowFunctionKey)!)
        case KeyCode.rightArrow: key = String(UnicodeScalar(NSRightArrowFunctionKey)!)
        case KeyCode.upArrow: key = String(UnicodeScalar(NSUpArrowFunctionKey)!)
        case KeyCode.downArrow: key = String(UnicodeScalar(NSDownArrowFunctionKey)!)
        case KeyCode.returnKey: key = "\r"
        case KeyCode.delete: key = "\u{8}"
        default:
            guard let name = Self.translate(keyCode), name.count == 1 else { return nil }
            key = name.lowercased()
        }
        var flags: NSEvent.ModifierFlags = []
        if modifiers & Self.control != 0 { flags.insert(.control) }
        if modifiers & Self.option != 0 { flags.insert(.option) }
        if modifiers & Self.shift != 0 { flags.insert(.shift) }
        if modifiers & Self.command != 0 { flags.insert(.command) }
        return (key, flags)
    }
}

enum HotKeyTarget: Hashable {
    case snap(SnapAction)
    case zone(display: String, zone: UUID)
    /// The nth pinned app, counting from 1.
    case pinnedApp(Int)
}

/// Global shortcuts via Carbon `RegisterEventHotKey` (spec §3.4): no extra permission, consumes the
/// keystroke, and reports a conflict when another app already owns the combo.
final class HotKeys: ObservableObject {
    static let shared = HotKeys()

    /// Targets whose shortcut another app already holds.
    @Published private(set) var unavailable: Set<HotKeyTarget> = []
    /// Called with each pressed shortcut's target.
    var onTrigger: (HotKeyTarget) -> Void = { _ in }
    /// Zone shortcuts, supplied by the zone store.
    var zoneBindings: () -> [(HotKeyTarget, Shortcut)] = { [] }

    private var registered: [UInt32: (ref: EventHotKeyRef, target: HotKeyTarget)] = [:]
    private var nextID: UInt32 = 1
    private var suspendCount = 0
    private var cancellables = Set<AnyCancellable>()
    private static let signature: OSType = 0x5354_5241 // "STRA"

    func start() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ in
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr, id.signature == HotKeys.signature else { return OSStatus(eventNotHandledErr) }
            HotKeys.shared.fire(id.id)
            return noErr
        }, 1, &spec, nil, nil)

        Settings.shared.$hotKeysEnabled.combineLatest(Settings.shared.$appHotKeysEnabled)
            .map { [$0, $1] }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.registerAll() } }
            .store(in: &cancellables)
        registerAll()
    }

    /// ⌃⌥1–9, like ⊞1–9 on Windows.
    static let pinnedAppBindings: [(HotKeyTarget, Shortcut)] = KeyCode.digits.enumerated().map {
        (.pinnedApp($0.offset + 1), Shortcut(keyCode: $0.element, modifiers: Shortcut.control | Shortcut.option))
    }

    /// Re-registers every shortcut: the fixed snap and pinned-app sets (if enabled) plus zone shortcuts.
    func registerAll() {
        for (_, entry) in registered { UnregisterEventHotKey(entry.ref) }
        registered.removeAll()
        guard suspendCount == 0 else { return }

        var bindings: [(HotKeyTarget, Shortcut)] = []
        if Settings.shared.hotKeysEnabled {
            bindings += SnapAction.allCases.map { (.snap($0), $0.defaultShortcut) }
        }
        if Settings.shared.appHotKeysEnabled {
            bindings += Self.pinnedAppBindings
        }
        bindings += zoneBindings()

        var taken = Set<HotKeyTarget>()
        for (target, shortcut) in bindings {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: nextID)
            let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id, GetEventDispatcherTarget(),
                                             OptionBits(kEventHotKeyExclusive), &ref)
            if status == noErr, let ref {
                registered[nextID] = (ref, target)
                nextID += 1
            } else {
                taken.insert(target)
                Log.info("shortcut \(shortcut.displayString) is in use elsewhere (status \(status))")
            }
        }
        unavailable = taken
        Log.info("registered \(registered.count) shortcut(s)")
    }

    /// Stops all shortcuts while one is being recorded, so they don't fire mid-capture.
    func suspend() {
        suspendCount += 1
        registerAll()
    }

    func resume() {
        suspendCount = max(0, suspendCount - 1)
        registerAll()
    }

    private func fire(_ id: UInt32) {
        guard let target = registered[id]?.target else { return }
        Log.info("shortcut fired: \(target)")
        onTrigger(target)
    }
}

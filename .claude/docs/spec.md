# Technical Spec: Strata for macOS

Companion to [intent.md](intent.md), which covers the *what* and *why*. This document covers the *how*: stack, system APIs, architecture, build and distribution, and what we need in order to do it.

---

## 1. Overview

Strata is a native Swift app: AppKit for the bar, SwiftUI for the Settings and Zone Editor windows, with no Dock icon or menu bar (`LSUIElement = true`). It runs on macOS 14+ as a universal `arm64` + `x86_64` binary, has its own name, bundle ID (`local.strata.Strata`) and icon, and has no third-party dependencies.

---

## 2. Tech stack

| Layer | Choice | Why |
|---|---|---|
| Language | **Swift 5 language mode** on the Swift 6.4 toolchain | Native. Swift 5 mode avoids fighting strict-concurrency checks around C callbacks (AX, Carbon) that are main-thread-only anyway. |
| Bar UI | **AppKit** (`NSPanel`, custom `NSView` subclasses) | Needs precise control over window level, non-activating clicks, tracking areas, drag and context menus. SwiftUI can't do non-activating panels cleanly. |
| Settings and Zone Editor UI | **SwiftUI** hosted in `NSWindow` via `NSHostingController` | Forms, pickers, sliders and the grid editor are quicker to build and easier to maintain in SwiftUI. |
| State and reactivity | **Combine** (`ObservableObject`, `@Published`, `PassthroughSubject`) | Shared between the SwiftUI views and the AppKit controllers, and handles debouncing settings changes. |
| Persistence | **UserDefaults** for scalars and arrays; **Codable → JSON** blob in UserDefaults for zone layouts | Small data, no need for files or a database. |
| Build system | **Swift Package Manager** plus a shell script that assembles the `.app` bundle | Only Command Line Tools are installed (no Xcode), and SwiftPM is enough for an executable target. |
| Minimum OS | **macOS 14 Sonoma** | `SMAppService`, modern `NSRunningApplication.activate()` and current SwiftUI `Form` styles. |
| Architectures | `arm64` + `x86_64` universal | Build each slice with `--triple` and merge them with `lipo`. |

No third-party dependencies. Everything comes from Apple's SDK.

---

## 3. System APIs by feature

### 3.1 Window discovery and tracking
- **Accessibility (HIServices / ApplicationServices)**
  - `AXUIElementCreateApplication(pid)`, then `kAXWindowsAttribute` to list windows per app
  - Per window: `kAXTitleAttribute`, `kAXSubroleAttribute` (keep `AXStandardWindow` and `AXDialog`), `kAXMinimizedAttribute`, `kAXPositionAttribute` / `kAXSizeAttribute`, `AXFullScreen`
  - `AXUIElementSetMessagingTimeout` (~0.3 s) so one hung app can't freeze the bar
- **`AXObserver`** for live updates
  - App level: `AXWindowCreated`, `AXFocusedWindowChanged`, `AXMainWindowChanged`, `AXApplicationHidden/Shown`
  - Window level: `AXUIElementDestroyed`, `AXTitleChanged`, `AXWindowMiniaturized/Deminiaturized`, `AXWindowMoved/Resized`
  - Run-loop source attached to the main run loop
- **`NSWorkspace` notifications**: app launch, terminate, activate, hide, unhide, and `activeSpaceDidChange`
- **Window identity**: `_AXUIElementGetWindow` (private, but stable for 10+ years) maps an AX element to its `CGWindowID`. That ID is our stable key for ordering and de-duplication.
- **Current-Space filtering**: `CGWindowListCopyWindowInfo(.optionOnScreenOnly)`, layer 0. A window counts as "on this Space" if it's on screen, minimised, or its app is hidden.
  - We only read `kCGWindowNumber`, `kCGWindowLayer`, `kCGWindowOwnerPID` and `kCGWindowBounds`. Those **don't need Screen Recording permission**. `kCGWindowName` does, so titles always come from AX.
  - Optional upgrade: `CGSCopySpacesForWindows` (SkyLight, private) for exact per-Space membership. We'll only add it if the public approach turns out to be insufficient.
- **Safety-net poll**: a 2 s timer, because some apps (notably Electron apps) fire AX notifications inconsistently.

### 3.2 Window actions
| Action | API |
|---|---|
| Focus | `AXRaise` action + `kAXMainAttribute = true` + `NSRunningApplication.activate()` |
| Minimise / restore | `kAXMinimizedAttribute` |
| Close | press `kAXCloseButtonAttribute` |
| Quit app | `NSRunningApplication.terminate()` |
| New window | walk `kAXMenuBarAttribute` for a "New Window" item and `AXPress` it; fall back to a synthesised ⌘N via `CGEvent` |
| Launch pinned app | `NSWorkspace.urlForApplication(withBundleIdentifier:)` + `openApplication(at:configuration:)` |
| Quit apps without windows | `CGWindowListCopyWindowInfo(.optionAll)` to find regular apps with no layer-0 window of at least 60×60 px on any Space; Finder excluded |

### 3.3 Window snapping and zones
- Move and resize through `kAXPositionAttribute` / `kAXSizeAttribute`, written size → position → size (some apps clamp size against the old position).
- **Temporarily turn off `AXEnhancedUserInterface`** on the app while moving. Chromium and Electron apps animate or ignore frame changes otherwise.
- **Coordinate systems**: AX and CG use a top-left origin anchored to the primary display; Cocoa uses bottom-left. One `ScreenGeometry` helper owns every conversion.
- **Work area** = `NSScreen.visibleFrame` minus the bar's height on screens that have a bar.
- **Restore**: keep each window's pre-snap frame in memory, keyed by `CGWindowID`.
- **Zones**: a grid per display (column and row fractions) plus named cell ranges, each with an optional shortcut. Displays are keyed by `CGDisplayCreateUUIDFromDisplayID`, which stays stable across reboots and reconnects, unlike `CGDirectDisplayID`.
- **Shift-drag to a zone**: `NSEvent.addGlobalMonitorForEvents` for `leftMouseDown/Dragged/Up`, a transparent, click-through `NSPanel` overlay, and on release, move the focused window into the zone under the cursor.

### 3.4 Global keyboard shortcuts
- **Carbon `RegisterEventHotKey`** + `InstallEventHandler(kEventHotKeyPressed)`. It needs no extra permission, it consumes the keystroke, and it **reports a conflict** when another app already owns the combo. That conflict shows up in Settings as "in use elsewhere".
- Default bindings use ⌃⌥ + key (arrows for halves; U/I/J/K for quarters; D/F/G for thirds; E/T for two-thirds; ↩ maximise; C centre; ⌫ restore; ⌃⌥⌘ ←/→ for displays). These match Rectangle's conventions, which most Mac users already know. **They're fixed in v1** (not rebindable), with one `hotKeysEnabled` switch to turn them all off.
- Shortcut recording in the Zone Editor uses a local `NSEvent` key-down monitor. Registered hotkeys are suspended while recording so they don't fire mid-capture.
- Key names come from `TISCopyCurrentKeyboardLayoutInputSource` + `UCKeyTranslate`, so labels match non-US layouts.

### 3.5 The bar itself
- One `NSPanel` per display, `styleMask: [.borderless, .nonactivatingPanel]`, so clicking the bar never takes focus away from the user's window.
- Level: `CGWindowLevelForKey(.dockWindow)`. Collection behaviour: `.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone`.
- Background: `NSVisualEffectView` (blur), with alpha taken from the opacity setting.
- Custom `NSView` buttons with `NSTrackingArea` for hover; `mouseDown/Dragged/Up` for click and drag-reorder; `rightMouseDown` → `NSMenu.popUpContextMenu`; `otherMouseUp` (button 2) for middle-click.
- **Pinned and window merge:** bar order is `[Start] [slot…]`, with one slot per pinned bundle ID in pinned order, followed by unpinned apps' windows in tracker order.
  - A pinned slot with no windows on this bar renders a `PinnedButton` (launcher).
  - A pinned slot with windows renders that app's `WindowButton`s in place of the launcher.
  - Dragging reorders pinned slots (persisted to `pinnedBundleIDs`) or unpinned windows (`WindowTracker.applyOrder`). A drag can't move a window across a pinned slot boundary.
- Custom hover tooltip panel, because `NSView.toolTip` is unreliable in a panel belonging to an inactive app.
- Rebuilds on `NSApplication.didChangeScreenParametersNotification` when monitors are added, removed or rearranged.

### 3.6 Overlap guard
- When a window moves or resizes (via AX notifications, debounced 300 ms), check whether its bottom edge goes under the bar. If it does, shrink the window so it ends at the bar's top edge, or move it up if it's too short to shrink.
- Skip while `NSEvent.pressedMouseButtons != 0` so we never fight a drag the user is still doing. Skip full-screen windows.

### 3.7 Start button
- Apps menu: scan `/Applications`, `/Applications/Utilities`, `/System/Applications`, `/System/Applications/Utilities` and `~/Applications`, with icons from `NSWorkspace.icon(forFile:)`. `NSMenu` type-to-select works as the search.
- Spotlight and Raycast: a synthesised `CGEvent` for ⌘Space and ⌥Space respectively.

### 3.8 System integration
| Feature | API |
|---|---|
| Launch at login | `SMAppService.mainApp.register()` / `.unregister()` (macOS 13+); only works from a real `.app` bundle |
| Move and auto-hide the Dock | `Process` running `defaults write com.apple.dock autohide -bool true`, `… orientation -string left`, then `killall Dock` |
| Permission prompt | `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])`, then poll `AXIsProcessTrusted()` every second until granted |
| Light/dark | `NSAppearance(named: .aqua / .darkAqua)` or `nil` to follow the system |

---

## 4. Architecture

```
main.swift ─► AppDelegate
               ├─ Settings (singleton, ObservableObject, UserDefaults)
               ├─ ZoneStore (singleton, JSON in UserDefaults)
               ├─ WindowTracker ── AXObserver / NSWorkspace / 2s poll
               │     └─ publishes [TrackedWindow], focusedWindowID
               ├─ BarController ── one BarPanel per NSScreen
               │     └─ BarContentView
               │          ├─ StartButton
               │          ├─ PinnedButton × n
               │          └─ WindowButton × n      (all subclass BarItemView)
               ├─ HotKeys ── Carbon ─► WindowMover / zones
               ├─ OverlapGuard
               ├─ ZoneGridOverlay (shift-drag) ─► ZoneOverlay
               ├─ SettingsWindow (SwiftUI SettingsView)
               └─ ZoneEditorWindow (SwiftUI ZoneEditorView + ZoneEditorModel)

Stateless helpers: AX, ScreenGeometry, WindowActions, WindowMover, SnapAction, Shortcut, AppList, DockSetup, LoginItem
```

**Data flow:** OS event → `WindowTracker.scheduleRefresh()` (50 ms coalescing) → full re-scan → diff against the previous list → `didChange` → `BarController` filters per display → `BarContentView.update(...)`, which reuses existing button views by `CGWindowID` so nothing flickers.

**Threading:** everything runs on the main thread. AX calls are synchronous but time-boxed by the messaging timeout. If profiling shows hitches with many apps open, move the AX scan to a serial background queue and publish the results back on main.

### Planned source layout
```
Strata/
├── Package.swift
├── Resources/
│   ├── Info.plist
│   └── AppIcon.icns          (our own icon, built with iconutil)
├── Sources/Strata/
│   ├── main.swift, AppDelegate.swift
│   ├── Settings.swift
│   ├── AX.swift               (AX wrappers + ScreenGeometry)
│   ├── WindowTracker.swift    (TrackedWindow, WindowRef)
│   ├── WindowActions.swift
│   ├── WindowMover.swift      (SnapAction)
│   ├── HotKeys.swift          (Shortcut, HotKeyTarget)
│   ├── Zones.swift            (Zone, ZoneLayout, ZoneStore, overlays)
│   ├── BarController.swift    (BarPanel, OverlapGuard)
│   ├── BarItemView.swift      (MenuAction, HoverTip)
│   ├── BarButtons.swift       (Start/Pinned/Window buttons, AppList)
│   ├── BarContentView.swift
│   ├── SettingsView.swift
│   ├── ZoneEditor.swift
│   └── SystemIntegration.swift (LoginItem, DockSetup)
├── Tests/StrataTests/        (pure-logic tests)
└── scripts/
    ├── build-app.sh           (swift build → .app → codesign)
    └── make-icon.sh
```

---

## 5. Permissions, signing and distribution

| Concern | Decision |
|---|---|
| **Accessibility (TCC)** | Required. Without it the app shows only the bar and a "Grant Accessibility" prompt. |
| **Screen Recording** | **Not** required. We never read window titles or pixels from CG. |
| **App Sandbox** | **Off.** AX control of other apps doesn't work in the sandbox, so the **Mac App Store is not an option.** |
| **Code signing in development** | TCC ties the Accessibility grant to the code signature. Ad-hoc signing (`codesign -s -`) changes with every build, so **macOS forgets the permission after each rebuild.** Fix: create a self-signed "Strata Dev" certificate in Keychain Access and sign every build with it. |
| **Public distribution** | **GitHub Releases**, not notarized: the universal release build, signed with "Strata Dev", zipped with `ditto` and attached to each release. On first launch users click **Open Anyway** in System Settings → Privacy & Security, then grant Accessibility. Because every version is signed by the same certificate, the Accessibility grant survives updates, so the "Strata Dev" certificate and its private key must be backed up. Notarization (Apple Developer Program, $99/yr → *Developer ID Application* certificate → hardened runtime → `notarytool submit` → `stapler staple`) would remove the Open Anyway step; not planned for now. |
| **Private API exposure** | `_AXUIElementGetWindow` (and the optional SkyLight CGS calls) are fine outside the App Store, but they're undocumented and could break in a future macOS. Each one sits behind a single wrapper so it's easy to swap. |

---

## 6. Build and run (no Xcode)

```bash
swift build -c release --triple arm64-apple-macosx14.0
swift build -c release --triple x86_64-apple-macosx14.0
lipo -create .build/arm64-apple-macosx/release/Strata \
             .build/x86_64-apple-macosx/release/Strata \
     -output build/Strata.app/Contents/MacOS/Strata
cp Resources/Info.plist   build/Strata.app/Contents/
cp Resources/AppIcon.icns build/Strata.app/Contents/Resources/
codesign --force --sign "Strata Dev" build/Strata.app
open build/Strata.app
```

`scripts/build-app.sh` wraps all of this. During day-to-day work an arm64-only debug build is enough. Logs go through `NSLog` (prefixed `Strata:`); view them with `log stream --predicate 'process == "Strata"'`.

---

## 7. Testing

| What | How |
|---|---|
| Snap geometry (`SnapAction.frame`), zone math (`unitRect`, `resized`), coordinate conversion, `Shortcut` display/encoding, ordering/grouping logic | Unit tests, using **Swift Testing**, which ships with the Swift 6 toolchain (check it works under Command Line Tools; fall back to XCTest if not). These need no permissions. |
| Window tracking, focus, minimise, close, new window | Manual test matrix against Finder, Safari, Terminal, a Chromium browser, VS Code (Electron), Microsoft Office, and a full-screen app |
| Multi-display | Two monitors (or a Mac plus a Sidecar iPad): bar per display, windows per display, move to next/previous display, zones per display, unplug/replug |
| Spaces and Stage Manager | Several Spaces, full-screen Spaces, Stage Manager on and off |
| Hotkey conflicts | Bind a conflicting shortcut in another app (e.g. Rectangle) and confirm "in use elsewhere" appears |
| Permission flow | `tccutil reset Accessibility local.strata.Strata`, then a first-launch run-through |

---

## 8. Resources we need

### Tools (already on this machine)
- macOS 27, Apple Silicon
- Swift 6.4 toolchain via **Command Line Tools** (`/Library/Developer/CommandLineTools`)
- Built-in CLIs: `swift`, `lipo`, `codesign`, `iconutil`, `plutil`, `log`, `tccutil`

### Tools (optional, recommended)
- **Xcode**: not required, but gives a debugger UI, Instruments (to profile AX scan cost) and the Accessibility Inspector
- **Accessibility Inspector** (ships with Xcode): essential for seeing what AX attributes stubborn apps expose
- A **self-signed code-signing certificate** (free, made in Keychain Access), so the Accessibility permission survives rebuilds

### Accounts
- **Apple Developer Program** ($99/yr), only if we distribute publicly with notarization. Not needed for personal use.

### Hardware
- A second display for multi-monitor testing (an external monitor or an iPad with Sidecar)
- Ideally access to an Intel Mac, or a Rosetta run, to smoke-test the `x86_64` slice

### Design assets
- An original app icon (1024×1024 master → `.iconset` → `iconutil -c icns`)
- SF Symbols for the in-bar glyphs (free, system-provided; the SF Symbols app helps us browse them)

### Documentation
- Apple: [Accessibility API (`AXUIElement`)](https://developer.apple.com/documentation/applicationservices/axuielement_h), [`NSPanel`](https://developer.apple.com/documentation/appkit/nspanel), [`CGWindowListCopyWindowInfo`](https://developer.apple.com/documentation/coregraphics/1455137-cgwindowlistcopywindowinfo), [`SMAppService`](https://developer.apple.com/documentation/servicemanagement/smappservice), [Notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- Carbon hotkeys: `Carbon/HIToolbox/CarbonEvents.h` and `Events.h` in the SDK headers (`xcrun --show-sdk-path`)

### Prior art to study (read for approach only, don't copy code)
- **Rectangle** (MIT): window snapping, AX quirks, `AXEnhancedUserInterface` handling
- **AltTab** (GPL-3.0): window enumeration across Spaces, private CGS/SkyLight usage. **GPL: read it, never paste from it.**
- **yabai** (MIT): Space and display internals

---

## 9. Risks

| Risk | Mitigation |
|---|---|
| AX is slow or hangs on unresponsive apps | Messaging timeout, coalesced refreshes, background-queue scan if needed |
| Electron and Chromium apps report AX events or frames inconsistently | 2 s poll; toggle `AXEnhancedUserInterface` during moves |
| Private APIs change in a future macOS | Isolated in one place each, with public-API fallbacks where they exist |
| Accessibility permission lost after every rebuild | Stable self-signed certificate (see §5) |
| Stage Manager and full-screen Spaces interact oddly with a `.dockWindow`-level panel | Test early; adjust level and collection behaviour |
| Conflict with the system Dock at the bottom edge | "Move & auto-hide Dock" option; work area accounts for the bar |
| Global shortcuts clash with other window managers | Carbon reports the conflict; show it in the UI; let the user turn off built-in snapping |

---

## 10. Decisions

| # | Question | Decision |
|---|---|---|
| 1 | Pinned apps vs. open windows | **Merge** (Windows 11 style). A pinned app shows as a launcher only while it has no windows on the current bar; once it does, its window buttons take the pin's slot. See §3.5. |
| 2 | Rebindable snap shortcuts in v1? | **No.** Fixed defaults (§3.4) with one global on/off switch. Zone shortcuts stay user-recordable. Rebinding can come in v2. |
| 3 | Auto-updater? | **No for v1.** Updates are manual downloads. Revisit (Sparkle + notarization) if we distribute publicly. |
| 4 | Name and icon | **Strata**, bundle ID `local.strata.Strata`. Swap in a reverse-DNS ID on a domain we own if we distribute publicly. Icon: original artwork, still to be designed. |

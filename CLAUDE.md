# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project status

**Strata** is a Windows-style taskbar for macOS: one button per window, pinned apps, a Start button, window snapping, custom zones.

Phase 0 (workspace + signing) is done; the app is still a placeholder `main.swift`. Read the planning docs before starting work:
- [.claude/docs/intent.md](.claude/docs/intent.md): what the app does and why (user-facing)
- [.claude/docs/spec.md](.claude/docs/spec.md): stack, system APIs per feature, architecture, signing, testing. `§` references in the plan point here.
- [.claude/docs/plans.md](.claude/docs/plans.md): 15 build phases (0–14), done in order, each with a "✅ Done when" checklist. Don't start a phase until the previous one's checklist passes, and commit at the end of each phase.

Layout so far: `Package.swift` (tools 5.9 → Swift 5 mode, one executable target), `Sources/Strata/`, `Resources/Info.plist` (copied verbatim into the bundle), `scripts/build-app.sh`. Keep this file in sync with the real commands and layout as phases land.

## Stack and constraints

- Swift 6.4 toolchain in **Swift 5 language mode**, via **Command Line Tools only (no Xcode)**. The build uses SwiftPM plus a shell script that assembles the `.app`. There are no third-party dependencies.
- macOS 14+, universal `arm64` + `x86_64` (the universal build only arrives in Phase 14).
- AppKit for the bar (`NSPanel`, custom `NSView`s). SwiftUI, hosted in `NSWindow`, for the Settings and Zone Editor windows. Combine for shared state.
- `LSUIElement = true`, accessory activation policy: no Dock icon and no menu bar. Windows the app shows (Settings) must call `NSApp.activate()` first.
- Bundle ID is `local.strata.Strata`. Logs use `NSLog` with the prefix `Strata:`.
- The App Sandbox is **off**, because AX control of other apps needs that. That rules out the Mac App Store.

## Commands (see spec §6; `swift test` arrives with tests in Phase 14)

```bash
swift build                                   # dev build
scripts/build-app.sh [--open]                 # arm64 debug build → build/Strata.app → codesign "Strata Dev"
swift test                                    # unit tests (Swift Testing; fall back to XCTest if unavailable under CLT)
swift test --filter <TestName>                # single test
log stream --predicate 'process == "Strata"'  # view logs
tccutil reset Accessibility local.strata.Strata  # re-test first-launch permission flow
codesign -dv build/Strata.app                 # should show Authority=Strata Dev
```

**Signing matters.** The Accessibility grant is tied to the code signature, so every build must be signed with the self-signed **"Strata Dev"** certificate. Ad-hoc signing (`-s -`) makes macOS forget the permission after each rebuild. `SMAppService` (launch at login) also works only from the real `.app` bundle, not from the `swift build` binary.

## Architecture (spec §4)

```
AppDelegate
 ├─ Settings (ObservableObject singleton over UserDefaults) / ZoneStore (JSON in UserDefaults, keyed by display UUID)
 ├─ WindowTracker ── AXObserver + NSWorkspace notifications + 2s safety poll
 ├─ BarController ── one BarPanel per NSScreen ─ BarContentView ─ Start/Pinned/WindowButton (all BarItemView)
 ├─ HotKeys (Carbon RegisterEventHotKey) ─► WindowMover / zones
 ├─ OverlapGuard, ZoneGridOverlay (shift-drag)
 └─ SettingsWindow, ZoneEditorWindow (SwiftUI)
```

**Data flow:** OS event → `WindowTracker.scheduleRefresh()` (50 ms coalescing) → full re-scan → diff → `didChange` → `BarController` filters per display → `BarContentView.update(...)`, which **reuses button views by `CGWindowID`** so nothing flickers. Everything runs on the main thread, and a ~0.3 s AX messaging timeout keeps one hung app from freezing the bar.

Things that need reading across several files:
- **Window identity** is `CGWindowID`, taken from the private `_AXUIElementGetWindow`. It's the key for ordering, de-duplication, view reuse and snap-restore frames. Keep each private API behind a single wrapper.
- **Coordinates:** AX/CG use a top-left origin at the primary display, Cocoa uses bottom-left. All conversion goes through `ScreenGeometry` and nowhere else. The work area is `visibleFrame` minus the bar height.
- **Current-Space filtering** uses `CGWindowListCopyWindowInfo(.optionOnScreenOnly)`, reading only number, layer, PID and bounds. **Never read `kCGWindowName`**: that needs Screen Recording permission, which the app deliberately doesn't ask for. Titles always come from AX.
- **Pinned/window merge** (Windows 11 style): the bar order is `[Start] [one slot per pinned bundle ID] [unpinned windows]`. A pinned slot shows its `WindowButton`s if the app has windows on that bar, otherwise a `PinnedButton`. A drag never crosses the pinned/unpinned boundary. Pinned order is saved to `pinnedBundleIDs`, window order to `WindowTracker.applyOrder`.
- **Moving windows:** write size → position → size, and turn off `AXEnhancedUserInterface` during the move, or Chromium/Electron apps misbehave.
- **The bar panel** is `[.borderless, .nonactivatingPanel]` at `.dockWindow` level with `canBecomeKey = false`, so clicking it must never steal focus.
- **Snap hotkeys** are fixed in v1 (⌃⌥ + key, Rectangle conventions) with a single `hotKeysEnabled` switch. Zone shortcuts can be recorded by the user. Hotkeys are suspended while a shortcut is being recorded.
- `MenuAction` (an `NSMenuItem` that runs a closure) must never be `copy()`'d, because copying drops the closure.
- OverlapGuard skips windows while `NSEvent.pressedMouseButtons != 0` and skips full-screen windows, so it never fights a drag the user is still doing.

## Testing

Unit tests cover only pure logic: `SnapAction.frame`, zone math, coordinate round-trips, `Shortcut` encoding, group-by-app ordering. Anything that touches AX, Spaces or displays is checked by hand against the matrix in spec §7 (Safari, Finder, Terminal, Chrome, an Electron app, full-screen apps, multiple displays, Stage Manager).

## Prior art

You can read Rectangle (MIT), AltTab (GPL-3.0) and yabai (MIT) to learn their approach. **Never paste code from AltTab (GPL).**

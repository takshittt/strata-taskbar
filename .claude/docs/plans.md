# Build Plan: Strata

A step-by-step guide to building Strata from an empty folder to a working, signed `.app`. Read [intent.md](intent.md) for what we're building and [spec.md](spec.md) for how; this file covers **the order we do it in**.

**How to use this plan**
- Work through the phases in order. Each phase builds on the one before.
- Each phase ends with a **✅ Done when** checklist. Don't start the next phase until every box is ticked. Every phase should leave you with an app that builds and runs.
- `§` references point to sections in spec.md.
- Commit to git at the end of every phase.

---

## Phase 0: Set up the workspace

**Goal:** an empty project that builds, and a signing setup that keeps the Accessibility permission between builds.

1. Run `git init` in `~/Projects/Taskbar` and add a `.gitignore` covering `.build/`, `build/` and `.DS_Store`.
2. Create the self-signed certificate (§5):
   Keychain Access → Certificate Assistant → *Create a Certificate…* → Name **`Strata Dev`**, Identity Type *Self-Signed Root*, Certificate Type **Code Signing**.
   Check it with `security find-identity -p codesigning -v`.
3. Create `Package.swift`: tools version 5.9, executable target **`Strata`**, platform `.macOS(.v14)`, Swift 5 language mode (§2).
4. Create `Resources/Info.plist` with `CFBundleExecutable = Strata`, `CFBundleIdentifier = local.strata.Strata`, `LSUIElement = true`, `LSMinimumSystemVersion = 14.0`.
5. Add a placeholder `Sources/Strata/main.swift` that just prints "hello".
6. Write `scripts/build-app.sh` (§6). It runs `swift build`, creates `build/Strata.app/Contents/{MacOS,Resources}`, copies the binary and the plist, runs `codesign --force --sign "Strata Dev"`, and optionally opens the app. Use arm64 debug for now; the universal build comes in Phase 14.

✅ **Done when**
- [ ] `swift build` succeeds
- [ ] `scripts/build-app.sh` produces `build/Strata.app`
- [ ] `codesign -dv build/Strata.app` shows `Authority=Strata Dev`

---

## Phase 1: App skeleton and permission flow

**Goal:** a background app that launches, asks for Accessibility, and knows when it has been granted.

1. `main.swift`: create `NSApplication`, set `AppDelegate`, call `setActivationPolicy(.accessory)`, run.
2. `AppDelegate.applicationDidFinishLaunching`: call `AX.promptForTrust()` if not trusted, then poll `AXIsProcessTrusted()` every second. When it flips to true, call `startServices()` (empty for now; it just logs).
3. `AX.swift`: the typed wrappers from §3.1 (`value`, `string`, `bool`, `element`, `elements`, `frame`, `setFrame`, `perform`, `windowID` via `_AXUIElementGetWindow`, `app(pid)` with a 0.3 s timeout).
4. Also in `AX.swift`: `ScreenGeometry` with `axRect(fromCocoa:)`, `cocoaRect(fromAX:)`, `screen(for:)`, `displayID`, `displayKey` (§3.3). Leave out `workArea` until Phase 2.
5. Add a temporary "Quit" mechanism, because the app has no menu bar or Dock icon. Use a debug global hotkey, or `killall Strata`.

✅ **Done when**
- [ ] First launch shows the macOS Accessibility prompt
- [ ] After granting it, the log shows "trusted, starting services" with no relaunch needed
- [ ] Rebuild and relaunch: **no prompt the second time** (this proves the certificate setup works)
- [ ] `log stream --predicate 'process == "Strata"'` shows the app's logs

---

## Phase 2: An empty bar on screen

**Goal:** a blurred strip at the bottom of the main display that stays put across Spaces and never steals focus.

1. `Settings.swift`: the `ObservableObject` singleton with every key from §1 and a `changed` subject. Only `barHeight`, `opacity` and `appearance` are used in this phase.
2. `BarController.swift`: `BarPanel` (`NSPanel`, borderless + nonactivating, `.dockWindow` level, collection behaviour per §3.5, `canBecomeKey = false`).
3. `BarController.shared.start()`: create one panel on the main screen, with frame = screen bottom × `barHeight`.
4. `BarContentView.swift`: an `NSVisualEffectView` background plus a thin top separator line. Nothing else yet.
5. Add `ScreenGeometry.workArea(_:)`, which uses `BarController.hasBar(on:)`.

✅ **Done when**
- [ ] The bar appears at the bottom of the main display
- [ ] Clicking the bar does **not** change which app is frontmost (the title in the menu bar stays the same)
- [ ] Switching Spaces (⌃← / ⌃→) keeps the bar visible
- [ ] Light/dark mode changes the bar's look

---

## Phase 3: Track windows (no UI yet)

**Goal:** a reliable, live list of the user's windows on the current Space, shown in the log only.

1. `WindowTracker.swift`: the `TrackedWindow` struct and `WindowRef` (§3.1).
2. `refresh()`: loop over regular running apps, read AX windows, keep standard windows and dialogs, filter by current Space using `CGWindowListCopyWindowInfo(.optionOnScreenOnly)` OR minimised OR app hidden.
3. Ordering: keep an `order: [CGWindowID]` list; add new windows at the end and drop windows that are gone.
4. Live updates: `NSWorkspace` notifications, an `AXObserver` per app and per window (§3.1), `scheduleRefresh()` with 50 ms coalescing, and a 2 s safety poll.
5. Focus: `WindowRef.focused()`, which reads the frontmost app's focused window.
6. Publish `didChange` only when the list or the focused window actually changed. Log the list each time.

✅ **Done when**
- [ ] Opening, closing, minimising and renaming a window (e.g. a new Safari tab) updates the log within about 0.5 s
- [ ] Windows on another Space disappear from the list when you switch away, and come back when you return
- [ ] Minimised windows stay in the list, marked minimised
- [ ] Finder's desktop, menu extras and Strata's own panel are **not** in the list
- [ ] Tested with Safari, Finder, Terminal, VS Code or another Electron app, and Chrome

---

## Phase 4: Window buttons on the bar

**Goal:** the core experience. One button per window, and clicking switches to it.

1. `BarItemView.swift`: the base class with hover and pressed drawing, a tracking area, `acceptsFirstMouse = true`, and the `primaryClick` / `middleClick` / `contextMenu` hooks.
2. `BarButtons.swift`: `WindowButton` with the app icon, title label (font from `fontSize`, hidden when `showTitles` is off), a dimmed look when minimised, and an accent underline when focused.
3. `WindowActions.swift`: `focus`, `minimize`, `close`, `toggle` (focus, or minimise if already focused) (§3.2).
4. `BarContentView.update(pinned:windows:focusedID:)`: **reuse** buttons by `CGWindowID`, lay them out left to right, and squeeze widths when they don't fit (max ~200 pt, min = square icon).
5. Hook up `WindowTracker.didChange` → `BarController.updateContents()`.
6. Apply the `groupByApp` sort: each app's windows sit together, placed where that app's first window sits.

✅ **Done when**
- [ ] Every open window has a button with the right icon and title
- [ ] Clicking a button focuses that window, even one from a background app
- [ ] Clicking the focused window's button minimises it; clicking again restores it
- [ ] Middle-click closes the window
- [ ] The focused button stays highlighted as you switch windows any way (⌘Tab, clicking, etc.)
- [ ] 30+ windows open: buttons shrink to fit and nothing overflows off screen

---

## Phase 5: Start button and pinned apps (merged)

**Goal:** the left side of the bar works, with pinned apps merged with their windows as decided in §10.

1. `StartButton`: an SF Symbol icon. Click it to run `startAction`: the apps menu (`AppList`, §3.7), Spotlight (⌘Space) or Raycast (⌥Space).
2. `PinnedButton`: icon only. Click to launch the app, or focus its windows if they're on another display's bar. Middle-click opens a new window.
3. `WindowActions.launch(bundleID:)` and `openNewWindow(bundleID:)`. The latter presses the AX menu "New Window" item, falling back to ⌘N (§3.2).
4. Merge logic in `BarContentView` (§3.5): `[Start] [slot per pinned bundle ID] [unpinned windows]`. A pinned slot shows its `WindowButton`s if the app has windows on this bar, otherwise a `PinnedButton`.
5. Seed the default pins: Finder, Safari, Terminal.

✅ **Done when**
- [ ] With Safari closed, the bar shows the Safari icon; clicking it launches Safari
- [ ] Once a Safari window opens, the icon is **replaced** by the window button in the same spot
- [ ] Closing the last Safari window brings the plain icon back in the same spot
- [ ] The Start button opens the apps menu; typing a few letters jumps to an app; choosing one launches it
- [ ] The Spotlight and Raycast start actions work (Raycast only if installed)

---

## Phase 6: Right-click menus

**Goal:** everything the user can do to a window or app from the bar.

1. `MenuAction`: an `NSMenuItem` subclass that runs a closure. Never `copy()` one, because that drops the closure.
2. Window button menu: title header · Minimise/Restore · New Window · Close Window · Pin/Unpin app · Hide app from bar · Quit app. (Snap and Zones submenus come in Phases 10 and 12.)
3. Pinned button menu: New Window · Unpin · Quit (if running).
4. Bar background and Start button menu: Settings… · Zone Editor… · Quit Apps Without Windows (*n*) · About Strata · Quit Strata. Settings and Zone Editor stay disabled until their phases.
5. `WindowActions.appsWithoutWindows()` and `quitAppsWithoutWindows()` (§3.2).
6. `Settings.pin / unpin / hide / unhide`. The bar updates straight away.

✅ **Done when**
- [ ] Every menu item does what it says
- [ ] Pinning an app from a window's menu makes it stay after its windows close
- [ ] Hiding an app removes all its windows from the bar (to undo it, edit the defaults for now; Settings comes in Phase 9)
- [ ] "Quit Apps Without Windows" shows the right count and never quits Finder or apps with windows on other Spaces
- [ ] "Quit Strata" quits cleanly. Remove the temporary quit mechanism from Phase 1.

---

## Phase 7: Drag to reorder, and hover tips

**Goal:** the bar feels polished.

1. `BarItemView` drag: start after more than 4 px of horizontal movement; call `bar.continueDrag(_:atX:)` and `bar.endDrag(_:)`.
2. `BarContentView`: the dragged item follows the cursor; neighbours animate aside (`NSAnimationContext`). On drop, persist the new order: pinned slots go to `Settings.pinnedBundleIDs`, unpinned windows to `WindowTracker.applyOrder`. Don't let an item cross a pinned/unpinned boundary.
3. `HoverTip`: a custom tooltip panel after a 0.6 s delay, which switches instantly while moving between items (§3.5).
4. Bar alignment: `left` or `center` (centre the whole group, Start button included).

✅ **Done when**
- [ ] Dragging a window button reorders it, and the order survives windows opening and closing
- [ ] Dragging a pinned app reorders the pins, and the order survives relaunching Strata
- [ ] A click isn't mistaken for a drag, or the other way round
- [ ] Hovering shows "App — Window title" above the button
- [ ] Centre alignment looks right with 1, 5 and 30 items

---

## Phase 8: Multiple displays

**Goal:** a bar per display, each showing the right windows.

1. `BarController.rebuild()`: one panel per `NSScreen` (or the main screen only, per `barScope`). Rebuild on `didChangeScreenParametersNotification`.
2. `updateContents()`: filter windows per display by `ScreenGeometry.screen(for:)` when `windowScope == .thisDisplay`.
3. When a window moves between displays, its button moves between bars (the AX moved notification triggers a refresh).

✅ **Done when**
- [ ] Each display has its own bar, showing only its windows
- [ ] Dragging a window to the other display moves its button within about 0.5 s
- [ ] Unplugging and replugging the external display rebuilds the bars with no ghosts or duplicates
- [ ] The "Main display only" and "Windows on all displays" options behave correctly
- [ ] It works with displays of different heights and with the external display arranged to the left of or above the main one (tests the coordinate conversion)

---

## Phase 9: Settings window

**Goal:** every preference can be changed in a proper window.

1. `SettingsView.swift` (SwiftUI `Form`), with sections for:
   - **Appearance:** theme, alignment, bar height, font size, opacity, show titles
   - **Bar:** bar on (all displays / main only), windows shown (this display / all), group by app, start button action
   - **Pinned apps:** list with remove and drag-to-reorder; "Add…" via `NSOpenPanel` limited to `.app`
   - **Hidden apps:** list with "Show again"
   - **Window snapping:** enable built-in shortcuts, gap when snapping, shortcut list (read-only)
   - **Windows:** shrink windows that overlap the bar
   - **System:** launch at login, Dock setup, Accessibility status
   - **About:** version, copyright
2. `SettingsWindow`: an `NSWindow` hosting the view. Call `NSApp.activate()` before showing it, since an accessory app has to activate itself to take keyboard focus.
3. Turn on "Settings…" in the menus.

✅ **Done when**
- [ ] Every control changes the bar **live**, with no restart
- [ ] Every setting survives relaunching Strata
- [ ] The Settings window takes keyboard focus and closes with ⌘W
- [ ] Hidden apps can be un-hidden from here

---

## Phase 10: Window snapping and global shortcuts

**Goal:** snap any window with a keyboard shortcut or from its right-click menu.

1. `WindowMover.swift`: `SnapAction` with all 18 cases, `title`, `menuGroups`, `defaultShortcut` (fixed, §3.4) and `frame(in:current:gap:)`. Thirds run along the long edge so portrait displays work.
2. `WindowMover.perform`, `apply` (saves the pre-snap frame), `restore`, `move(to:)` / `move(by:)` for displays. Turn off `AXEnhancedUserInterface` during moves (§3.3).
3. `HotKeys.swift`: `Shortcut` (Codable, display string via `UCKeyTranslate`) and `HotKeys` using Carbon `RegisterEventHotKey`. Track `unavailable` for combos already taken.
4. Add a "Snap" submenu to the window button menu.
5. In Settings, show each shortcut and mark ones "in use elsewhere". The `hotKeysEnabled` switch registers or unregisters all of them.

✅ **Done when**
- [ ] All 18 actions work from the keyboard and from the menu
- [ ] Snapped windows sit **above** the bar, not under it
- [ ] "Restore" puts a window back where it was before its first snap
- [ ] Next/Previous Display keeps the window's relative position and size
- [ ] Works on Chrome and an Electron app, not just native apps
- [ ] With Rectangle running, conflicting shortcuts show "in use elsewhere" instead of failing silently
- [ ] The gap setting leaves even spacing between snapped windows

---

## Phase 11: Overlap guard

**Goal:** windows never hide under the bar.

1. `OverlapGuard` (§3.6): debounced check on window moved/resized/created and after bar rebuilds.
2. Shrink the window so its bottom sits at the bar's top edge, or move it up if it's shorter than 120 pt. Skip while the mouse is pressed; skip full-screen windows.

✅ **Done when**
- [ ] Dragging a window's bottom edge under the bar snaps it back to the bar's edge **after** you let go, not during the drag
- [ ] Maximising with the green button leaves the window above the bar
- [ ] The setting can be turned off
- [ ] No resize loops (watch the log for repeated resizes of the same window)

---

## Phase 12: Custom zones

**Goal:** users design their own layouts and send windows into them.

1. `Zones.swift` models: `CellRange`, `Zone`, `ZoneLayout` (`unitRect`, `resized`, `nextZoneName`, `zone(atUnit:)`) and `ZoneStore` (JSON in UserDefaults, keyed by display UUID) (§3.3).
2. `ZoneOverlay`: a click-through, full-screen panel that draws the zones, with one zone highlighted.
3. `ZoneEditorModel` + `ZoneEditorView` (SwiftUI):
   - display picker, column and row steppers, an "equalize" button
   - a grid you drag across to select cells; draggable dividers for column and row sizes
   - "Add Zone from Selection", with a check that the new zone doesn't overlap an existing one
   - zone list: rename, delete, record a shortcut (Esc cancels, ⌫ clears; registered hotkeys are suspended while recording)
   - "Preview on display" shows the `ZoneOverlay` for 1.5 s
4. `WindowMover.moveToCells(...)`, registered zone hotkeys (`HotKeyTarget.zone`), and a "Move to Zone" submenu on window buttons.
5. `ZoneGridOverlay`: Shift-drag a window to show the zones, then drop it into the highlighted zone (§3.3).

✅ **Done when**
- [ ] You can build a 3-column layout with a tall left zone and two stacked right zones
- [ ] A zone shortcut moves the focused window into that zone, even when the window is on another display
- [ ] Shift-dragging a window lights up zones under the cursor; releasing snaps the window
- [ ] Zones survive relaunching, and unplugging and replugging the display
- [ ] Shrinking the grid clips or drops zones that no longer fit, without crashing

---

## Phase 13: System integration

**Goal:** Strata behaves like a proper Mac utility.

1. `SystemIntegration.swift`:
   - `LoginItem` (`SMAppService.mainApp`), with errors shown in Settings
   - `DockSetup.moveAndAutoHide(to:)` (`defaults write` + `killall Dock`, §3.8), behind a confirmation dialog
2. Show Accessibility status live in Settings, with a button that opens the right System Settings pane.
3. An About panel: `NSApp.orderFrontStandardAboutPanel` with our name, version and copyright.

✅ **Done when**
- [ ] "Launch at login" works after logging out and back in
- [ ] Dock setup moves the Dock and turns on auto-hide, and asks before doing it
- [ ] Revoking Accessibility while Strata runs shows a clear message instead of a broken bar

---

## Phase 14: Tests, icon and release build

**Goal:** a finished, shippable v1.

1. **Unit tests** in `Tests/StrataTests` (§7) for `SnapAction.frame` (all 18 cases, landscape and portrait, with and without a gap), `ZoneLayout.unitRect`, `ZoneLayout.resized`, coordinate conversion round-trips, `Shortcut` encode/decode and display, and group-by-app ordering. Run them with `swift test`.
2. **Icon:** design a 1024×1024 master. `scripts/make-icon.sh` builds the `.iconset` sizes, runs `iconutil -c icns`, and outputs `Resources/AppIcon.icns`. Add `CFBundleIconFile` to Info.plist.
3. **Universal build:** extend `build-app.sh` with release builds for both triples plus `lipo` (§6), and check with `lipo -info`.
4. **Manual test pass:** go through the whole test matrix in §7.
5. **Performance check:** with 15 apps and 50 windows, a refresh takes under 30 ms and idle CPU is roughly 0%. Profile with Instruments if Xcode is installed.
6. Tag `v0.1.0` in git and zip `build/Strata.app`.

✅ **Done when**
- [ ] `swift test` passes
- [ ] `lipo -info` shows `x86_64 arm64`
- [ ] The app has its own icon in Finder and the About panel
- [ ] Every check from Phases 1–13 still passes
- [ ] Strata has run for a full working day without a crash or a stuck bar

---

## Later (not in v1)

- Rebindable snap shortcuts (decision 2)
- Auto-updates with Sparkle, plus Developer ID signing and notarization (decision 3)
- Exact per-Space window membership via SkyLight, if the public approach falls short
- Window thumbnail previews on hover (needs Screen Recording permission)

---

## Rough effort

| Phases | What | Estimate |
|---|---|---|
| 0–2 | Setup, skeleton, empty bar | 0.5–1 day |
| 3–4 | Window tracking + buttons (hardest part) | 2–3 days |
| 5–8 | Pins, menus, drag, multi-display | 2–3 days |
| 9 | Settings | 1 day |
| 10–11 | Snapping, hotkeys, overlap guard | 1–2 days |
| 12 | Zones | 2–3 days |
| 13–14 | Integration, tests, icon, release | 1–2 days |
| **Total** | | **~10–15 working days** for one developer |

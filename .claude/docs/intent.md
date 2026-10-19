# What We're Building: Strata, a Windows-Style Taskbar for Mac

## The short version

We're building **Strata**, a small Mac app that adds a **Windows-style taskbar** along the bottom of the screen: a strip that shows every open window, so you can see what's open and switch between windows with one click.

It also helps you **arrange windows neatly**, for example putting one window on the left half of the screen and another on the right, using a keyboard shortcut or a right-click.

## The problem it solves

On a Mac, the Dock at the bottom shows **apps**, not **windows**. If you have three Safari windows and two Word documents open, the Dock shows two icons, and finding the window you want takes extra clicks.

People coming from Windows are used to seeing each window as its own button. This app gives Mac users that.

## What the app will do

### 1. The bar at the bottom of the screen
- A bar runs along the bottom of the screen, like on Windows.
- **Every open window gets its own button**, showing the app's icon and, if you want, the window's name (for example "Budget.xlsx").
- **Click a button** to jump to that window. Click it again to minimise it.
- The window you're working in is **highlighted**, so you always know where you are.
- **Drag the buttons** to put them in any order you like.
- With more than one monitor, each one can have its own bar showing only the windows on that screen.

### 2. A "Start" button
- A button on the far left, like the Windows Start button.
- Clicking it opens a list of all your apps, or opens Spotlight or Raycast (the Mac's search tools), whichever you choose.

### 3. Pinned favourite apps
- Keep favourite apps (like Safari or Mail) on the bar at all times, even when they're closed.
- One click opens them.
- When a pinned app is open, its icon **turns into its window buttons**, the same as on Windows 11. When you close the app, the plain icon comes back. Each app only ever takes up one spot on the bar.
- To pin an app, right-click its window on the bar and choose "Pin".

### 4. Right-click menus
Right-click any window's button to:
- Minimise it, close it, or open a new window of the same app
- Pin or unpin the app
- Hide that app from the bar
- Quit the app
- Snap the window to a position on the screen (see below)

### 5. Snapping windows into place
Quickly resize and move a window into a set position:
- Left half, right half, top half, bottom half
- The four corners (quarter of the screen each)
- Thirds and two-thirds (handy on wide screens)
- Full screen, centred, or back to how it was before
- Move to the next or previous monitor

Each of these has a **keyboard shortcut**, so you never have to drag windows around by hand. The shortcuts are set for you in this first version (you can't change them yet), but you can switch them all off in Settings. If another app already uses a shortcut, Strata says so instead of fighting over it.

### 6. Custom "zones"
- Split your screen into your own layout of boxes, for example a big area on the left and two smaller ones stacked on the right.
- Give each zone a name and its own keyboard shortcut.
- **Hold Shift while dragging a window** and the zones light up. Let go over one and the window fills it.
- Each monitor can have its own layout.

### 7. Keeping things tidy
- Windows won't slide underneath the bar; the app nudges or shrinks them so nothing is hidden.
- A one-click option to **close apps that are running but have no windows open** (on a Mac, apps keep running after you close their last window).
- An option to move the Mac's own Dock out of the way and hide it automatically, so it doesn't clash with the new bar.

### 8. Settings you can change
- Light mode, dark mode, or match the system
- Buttons on the left or in the centre (like Windows 11)
- Bar height, text size, and how see-through the bar is
- Show or hide window names on the buttons
- Keep each app's windows grouped together
- A bar on every monitor, or only the main one
- Start automatically when you log in to your Mac

## What it needs from you

To see and move other apps' windows, Strata needs a Mac permission called **Accessibility**. The first time it runs, macOS asks you to allow it in **System Settings → Privacy & Security → Accessibility**. Without it, Strata can't see your windows.

## What it is *not*

- It does **not** replace or change macOS. It's a normal app that you can quit any time.
- It does **not** collect or send any of your data anywhere.

## Who it's for

- People switching from Windows to Mac who miss the taskbar
- Anyone who keeps lots of windows open and wants to find them faster
- People who like keeping windows neatly arranged side by side

## Updates

The first version won't update itself. When a new version comes out, you download it and replace the old one.

## Requirements

- A Mac running macOS 14 (Sonoma) or newer
- Works on both Apple Silicon (M1/M2/M3…) and older Intel Macs

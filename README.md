# Strata

**A Windows-style taskbar for your Mac.**

The Mac Dock shows one icon per app. Strata adds a bar at the bottom of your screen that shows **every open window as its own button**, the way Windows does. Click a button to jump to that window.

## What it does

- **One button per window.** Click to switch, click again to minimise. Right-click for the app's recent files and its other windows, like the Dock.
- **Start button.** Opens a list of your apps.
- **Pinned apps.** Keep your favourite apps on the bar, even when they're closed.
- **Snap windows.** Put a window on the left half, right half, a corner and more, with a keyboard shortcut or a right-click.
- **Custom zones.** Draw your own screen layout. Hold **Shift** while dragging a window to drop it into a zone, and add **⌃ Control** to stretch it across several zones.
- **Multiple monitors.** Each screen gets its own bar.

## Download

👉 **[Download the latest version](https://github.com/takshittt/strata-taskbar/releases/latest)**

On that page, click **`Strata-<version>.zip`** under **Assets**.

Works on **macOS 14 (Sonoma) or newer**, on both Apple silicon and Intel Macs. Strata is free.

## Install

**1. Move it to Applications**

Double-click the zip file to unzip it. Then drag **Strata** into your **Applications** folder.

**2. Open it the first time**

Strata is free, so it isn't registered with Apple (that costs money every year). Because of this, your Mac will block it the first time:

1. Open **Strata** from Applications. You'll see a warning. Click **Done** or **OK**.
2. Open **System Settings** → **Privacy & Security**.
3. Scroll down. Next to the message about Strata, click **Open Anyway**.
4. Enter your password if asked, then click **Open Anyway** again.

You only need to do this once.

**3. Give it permission**

Strata needs **Accessibility** permission to see and move your windows. Until you allow it, the bar says *"Strata needs Accessibility access — click to grant"*.

1. Click that message. It opens **System Settings → Privacy & Security → Accessibility**.
2. Turn on the switch next to **Strata**.

That's it. The bar will appear at the bottom of your screen.

## Snap shortcuts

Hold **Control + Option** (⌃⌥) and press:

| Key | Window goes to |
|---|---|
| ← → ↑ ↓ | Left, right, top or bottom half |
| U · I · J · K | Top-left, top-right, bottom-left, bottom-right corner |
| D · F · G | Left, middle or right third |
| E · T | Left or right two-thirds |
| Return | Fill the screen |
| C | Centre |
| Delete | Back to its old size |
| 1–9 | Open your 1st–9th pinned app |

Add **Command** (⌃⌥⌘ + ← / →) to move a window to the other monitor.

You can turn the shortcuts off in Settings.

## Settings

Right-click an empty spot on the bar to open **Settings**. There you can change the icon size, turn on **Launch at login**, and more.

## Updating

Download the new version and replace the old **Strata** in Applications. Your settings and permission are kept.

## Uninstall

1. Right-click the bar and choose **Quit Strata**.
2. Drag **Strata** from Applications to the Trash.

## Something not working?

- **Buttons don't show up or windows won't move:** check that Strata is turned on in **System Settings → Privacy & Security → Accessibility**. If it is, turn it off and on again.
- **Found a bug?** [Open an issue](https://github.com/takshittt/strata-taskbar/issues).

## For developers

Strata is written in Swift and builds with the Xcode Command Line Tools (no Xcode needed):

```bash
scripts/build-app.sh --open
```

The build is signed with a self-signed certificate named **Strata Dev**, which you'll need to create in Keychain Access first.

## License

[MIT](LICENSE)

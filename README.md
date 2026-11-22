# Mac Snap

Snap any Mac window into a half, a quarter or full screen — by dragging it to the screen edge, or with a shortcut. Like Magnet / Windows Snap.

## Install

```sh
git clone https://github.com/emi2git/mac-snap.git ~/git/apps/mac-snap
cd ~/git/apps/mac-snap
./build.sh
```

`build.sh` builds the app, installs it to `~/Applications/Mac Snap.app` and starts it.
Needs Xcode (or the Command Line Tools) for `swiftc`.

**First run:** macOS asks for **Accessibility** access — allow it in
System Settings › Privacy & Security › Accessibility (turn on *Mac Snap*). Without it nothing snaps.

## Run

- Double-click `~/Applications/Mac Snap.app` (it starts by itself at login — see menu).
- It has no Dock icon. It lives in the **top menu bar** as a small grid icon ▦, next to Wi‑Fi.
- Can't see it? On a MacBook with a notch, a full menu bar hides icons behind the notch.
  Hold ⌘ and drag the icon to move it, or quit some other menu-bar apps.

## Drag to snap

Drag a window by its title bar and push the mouse against the screen edge. A blue box shows where it will go; let go to snap.

| Drag mouse to…            | Window becomes   |
|---------------------------|------------------|
| Left edge                 | Left half        |
| Right edge                | Right half       |
| Top edge                  | Full screen      |
| Top-left corner           | Top-left quarter |
| Top-right corner          | Top-right quarter|
| Bottom-left corner        | Bottom-left quarter |
| Bottom-right corner       | Bottom-right quarter |

## Keyboard shortcuts

All use **⌃ Control + ⌥ Option**, and act on the front window.

| Shortcut   | Action              |
|------------|---------------------|
| ⌃⌥ ←       | Left half           |
| ⌃⌥ →       | Right half          |
| ⌃⌥ ↑       | Top half            |
| ⌃⌥ ↓       | Bottom half         |
| ⌃⌥ U       | Top-left quarter    |
| ⌃⌥ I       | Top-right quarter   |
| ⌃⌥ J       | Bottom-left quarter |
| ⌃⌥ K       | Bottom-right quarter|
| ⌃⌥ Return  | Full screen         |
| ⌃⌥ Delete  | Restore previous size |

## Menu bar options

Click the icon in the top bar:

- **Accessibility status** — ✓ when allowed; click to open the setting if not.
- **Left / Right / Top / Bottom Half, the four quarters, Maximize, Restore** — same as the shortcuts.
- **Menu Bar Icon** — pick the icon's look: Grid, Halves, Thirds, Window, Left Half, Squares.
- **Launch at Login** — on by default.
- **Quit Mac Snap**

## Test

```sh
swift Tests/e2e.swift
```

Drags a real Finder window to every edge/corner and presses every shortcut, then checks the window's frame.
(The terminal needs Accessibility access too.)

# Mac Snap

Snap any Mac window into a half, a quarter or full screen by dragging it to the screen edge. No keyboard shortcuts. Like Magnet / Windows Snap.

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
- It has no Dock icon. It lives in the **top menu bar**, next to Wi‑Fi.
- The icon **follows how you drag**: while you drag to an edge it shows that layout (left half, top-right quarter, full…), and afterwards it keeps showing the last layout you snapped to.
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

## Menu bar options

Click the icon in the top bar. There are no window commands here — snapping is done only by dragging.

- **Accessibility status** — ✓ when allowed; click to open the setting if not.
- **Help — How to Snap…** — opens a guide showing where to drag and what each spot does.
- **Launch at Login** — on by default.
- **Quit Mac Snap**

To unsnap a window, just drag it away and resize it as usual.

## Test

```sh
swift Tests/e2e.swift
```

Drags a real Finder window to every edge/corner then checks the window's frame and the menu-bar icon, that the menu has no window commands, and that Help opens.
(The terminal needs Accessibility access too.)

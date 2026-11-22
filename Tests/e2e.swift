// End-to-end test: drags a real Finder window to each edge/corner with synthetic mouse events,
// then the menu-bar menu items, and checks the window frame. Needs Mac Snap running + Accessibility for both.
//   swift Tests/e2e.swift
import AppKit
import ApplicationServices

func attr<T>(_ e: AXUIElement, _ n: String) -> T? { var v: CFTypeRef?; return AXUIElementCopyAttributeValue(e, n as CFString, &v) == .success ? v as? T : nil }
func frame(_ w: AXUIElement) -> CGRect {
    var p = CGPoint.zero, s = CGSize.zero
    AXValueGetValue(attr(w, kAXPositionAttribute)! as AXValue, .cgPoint, &p)
    AXValueGetValue(attr(w, kAXSizeAttribute)! as AXValue, .cgSize, &s)
    return CGRect(origin: p, size: s)
}
func setFrame(_ w: AXUIElement, _ r: CGRect) {
    var p = r.origin, s = r.size
    AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &s)!)
    AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &p)!)
}
func wait(_ s: Double) { RunLoop.current.run(until: Date().addingTimeInterval(s)) }
func mouse(_ t: CGEventType, _ p: CGPoint) { CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: p, mouseButton: .left)!.post(tap: .cghidEventTap) }

let scr = NSScreen.screens[0], f = scr.frame, v = scr.visibleFrame
func q(_ r: NSRect) -> CGRect { CGRect(x: r.minX, y: f.maxY - r.maxY, width: r.width, height: r.height) } // cocoa→quartz
let w2 = (v.width / 2).rounded(), h2 = (v.height / 2).rounded()
let halfL = NSRect(x: v.minX, y: v.minY, width: w2, height: v.height)
let expect: [String: NSRect] = [
    "left": halfL, "right": NSRect(x: v.minX + w2, y: v.minY, width: v.width - w2, height: v.height),
    "maximize": v, "top": NSRect(x: v.minX, y: v.minY + h2, width: v.width, height: v.height - h2),
    "bottom": NSRect(x: v.minX, y: v.minY, width: v.width, height: h2),
    "topLeft": NSRect(x: v.minX, y: v.minY + h2, width: w2, height: v.height - h2),
    "topRight": NSRect(x: v.minX + w2, y: v.minY + h2, width: v.width - w2, height: v.height - h2),
    "bottomLeft": NSRect(x: v.minX, y: v.minY, width: w2, height: h2),
    "bottomRight": NSRect(x: v.minX + w2, y: v.minY, width: v.width - w2, height: h2),
]
// Drag targets (quartz, top-left origin) on the primary screen's edges.
let edges: [(String, CGPoint)] = [
    ("left", CGPoint(x: 0, y: f.height / 2)), ("right", CGPoint(x: f.width - 1, y: f.height / 2)),
    ("maximize", CGPoint(x: f.width / 2, y: 0)), ("topLeft", CGPoint(x: 0, y: 0)),
    ("topRight", CGPoint(x: f.width - 1, y: 0)), ("bottomLeft", CGPoint(x: 0, y: f.height - 1)),
    ("bottomRight", CGPoint(x: f.width - 1, y: f.height - 1)),
]

NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory()))
wait(1.5)
let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder")[0]
finder.activate()
wait(0.5)
// A real Finder window (not the desktop, which also shows up as a window)
let wins: [AXUIElement] = attr(AXUIElementCreateApplication(finder.processIdentifier), kAXWindowsAttribute) ?? []
guard let win = wins.first(where: { (attr($0, kAXSubroleAttribute) as String?) == kAXStandardWindowSubrole }) else { print("no Finder window"); exit(1) }
AXUIElementPerformAction(win, kAXRaiseAction as CFString)
let original = frame(win)
var fails = 0
func check(_ name: String, _ how: String) {
    let got = frame(win), want = q(expect[name]!)
    let ok = abs(got.minX - want.minX) < 3 && abs(got.minY - want.minY) < 3 && abs(got.width - want.width) < 3 && abs(got.height - want.height) < 3
    if !ok { fails += 1 }
    print(ok ? "PASS" : "FAIL", how, name, ok ? "" : "got \(got) want \(want)")
}
let start = CGRect(x: f.width * 0.3, y: f.height * 0.3, width: 700, height: 450)

for (name, target) in edges {
    setFrame(win, start); wait(0.4)
    let grab = CGPoint(x: start.midX, y: start.minY + 12)   // title/toolbar strip
    mouse(.leftMouseDown, grab); wait(0.15)
    for i in 1...25 {
        let t = Double(i) / 25
        mouse(.leftMouseDragged, CGPoint(x: grab.x + (target.x - grab.x) * t, y: grab.y + (target.y - grab.y) * t)); wait(0.02)
    }
    wait(0.3)
    mouse(.leftMouseUp, target); wait(0.6)
    check(name, "drag  ")
    // Menu-bar icon shows the layout just used.
    let icon = UserDefaults(suiteName: "com.emi2git.emisnap")?.string(forKey: "lastZoneIcon") ?? "-"
    let wantIcon = ["left": "lefthalf", "right": "righthalf", "maximize": "rectangle.inset.filled", "topLeft": "topleft",
                    "topRight": "topright", "bottomLeft": "bottomleft", "bottomRight": "bottomright"][name]!
    if !icon.contains(wantIcon) { fails += 1 }
    print(icon.contains(wantIcon) ? "PASS" : "FAIL", "icon  ", name, icon)
}

// Menu-bar menu items act on the front window.
let snapApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.emi2git.emisnap")[0]
let extras: AXUIElement = attr(AXUIElementCreateApplication(snapApp.processIdentifier), kAXExtrasMenuBarAttribute)!
let statusItem = (attr(extras, kAXChildrenAttribute) as [AXUIElement]?)![0]
func pressMenu(_ title: String) {
    finder.activate(); wait(0.3)
    AXUIElementPerformAction(statusItem, kAXPressAction as CFString); wait(0.8)
    let menu = (attr(statusItem, kAXChildrenAttribute) as [AXUIElement]?)![0]
    let item = (attr(menu, kAXChildrenAttribute) as [AXUIElement]?)!.first { (attr($0, kAXTitleAttribute) as String?) == title }!
    AXUIElementPerformAction(item, kAXPressAction as CFString); wait(0.5)
}
let menuTitles = ["left": "Left Half", "right": "Right Half", "top": "Top Half", "bottom": "Bottom Half", "topLeft": "Top Left",
                  "topRight": "Top Right", "bottomLeft": "Bottom Left", "bottomRight": "Bottom Right", "maximize": "Maximize"]
for (name, title) in menuTitles.sorted(by: { $0.key < $1.key }) {
    setFrame(win, start); finder.activate(); wait(0.4)
    pressMenu(title)
    check(name, "menu  ")
}
pressMenu("Restore")
let r = frame(win), restoredOK = abs(r.minX - start.minX) < 3 && abs(r.width - start.width) < 3
if !restoredOK { fails += 1 }
print(restoredOK ? "PASS" : "FAIL", "menu   restore", restoredOK ? "" : "got \(r)")

// No keyboard shortcuts: ⌃⌥← must leave the window alone.
setFrame(win, start); finder.activate(); wait(0.4)
for down in [true, false] {
    let e = CGEvent(keyboardEventSource: nil, virtualKey: 123, keyDown: down)!
    e.flags = [.maskControl, .maskAlternate, .maskSecondaryFn, .maskNumericPad]; e.post(tap: .cghidEventTap)
}
wait(0.5)
let k = frame(win), untouched = abs(k.minX - start.minX) < 3 && abs(k.width - start.width) < 3
if !untouched { fails += 1 }
print(untouched ? "PASS" : "FAIL", "no shortcut (⌃⌥← does nothing)")
setFrame(win, original)
print(fails == 0 ? "ALL PASS" : "\(fails) FAILED")
exit(fails == 0 ? 0 : 1)

// End-to-end test: drags a real Finder window to each edge/corner with synthetic mouse events,
// then tries the ⌃⌥ hotkeys, and checks the window frame. Needs Emi Snap running + Accessibility for both.
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
guard let win: AXUIElement = attr(AXUIElementCreateApplication(finder.processIdentifier), kAXFocusedWindowAttribute) else { print("no Finder window"); exit(1) }
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
}

let keys: [(String, CGKeyCode)] = [("left", 123), ("right", 124), ("top", 126), ("bottom", 125),
                                    ("topLeft", 32), ("topRight", 34), ("bottomLeft", 38), ("bottomRight", 40), ("maximize", 36)]
for (name, code) in keys {
    setFrame(win, start); finder.activate(); wait(0.4)
    for down in [true, false] {
        let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
        e.flags = [.maskControl, .maskAlternate]
        if (123...126).contains(code) { e.flags.formUnion([.maskSecondaryFn, .maskNumericPad]) } // real arrow keys carry these
        e.post(tap: .cghidEventTap)
    }
    wait(0.5)
    check(name, "hotkey")
}
// Restore (⌃⌥⌫) returns to the pre-snap frame.
for down in [true, false] { let e = CGEvent(keyboardEventSource: nil, virtualKey: 51, keyDown: down)!; e.flags = [.maskControl, .maskAlternate]; e.post(tap: .cghidEventTap) }
wait(0.5)
let r = frame(win), restoredOK = abs(r.minX - start.minX) < 3 && abs(r.width - start.width) < 3
if !restoredOK { fails += 1 }
print(restoredOK ? "PASS" : "FAIL", "hotkey restore", restoredOK ? "" : "got \(r)")
setFrame(win, original)
print(fails == 0 ? "ALL PASS" : "\(fails) FAILED")
exit(fails == 0 ? 0 : 1)

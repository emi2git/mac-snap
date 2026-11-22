// Mac Snap — drag a window to a screen edge or corner to snap it (like Magnet / Windows Snap).
//   left / right edge  → half        corners → quarter        top edge → maximize
// No keyboard shortcuts — everything else is in the menu-bar icon.
import AppKit
import ApplicationServices
import ServiceManagement

// MARK: - Zones

enum Zone: String, CaseIterable {
    case left, right, top, bottom, topLeft, topRight, bottomLeft, bottomRight, maximize

    var title: String {
        switch self {
        case .left: "Left Half"; case .right: "Right Half"; case .top: "Top Half"; case .bottom: "Bottom Half"
        case .topLeft: "Top Left"; case .topRight: "Top Right"; case .bottomLeft: "Bottom Left"; case .bottomRight: "Bottom Right"
        case .maximize: "Maximize"
        }
    }

    /// Menu-bar icon showing this layout.
    var symbol: String {
        switch self {
        case .left: "rectangle.lefthalf.inset.filled"; case .right: "rectangle.righthalf.inset.filled"
        case .top: "rectangle.tophalf.inset.filled"; case .bottom: "rectangle.bottomhalf.inset.filled"
        case .topLeft: "rectangle.inset.topleft.filled"; case .topRight: "rectangle.inset.topright.filled"
        case .bottomLeft: "rectangle.inset.bottomleft.filled"; case .bottomRight: "rectangle.inset.bottomright.filled"
        case .maximize: "rectangle.inset.filled"
        }
    }

    /// Target rect in Cocoa coordinates (bottom-left origin) inside the screen's visible frame.
    func rect(in v: NSRect) -> NSRect {
        let w = (v.width / 2).rounded(), h = (v.height / 2).rounded()
        switch self {
        case .left:        return NSRect(x: v.minX, y: v.minY, width: w, height: v.height)
        case .right:       return NSRect(x: v.minX + w, y: v.minY, width: v.width - w, height: v.height)
        case .top:         return NSRect(x: v.minX, y: v.minY + h, width: v.width, height: v.height - h)
        case .bottom:      return NSRect(x: v.minX, y: v.minY, width: v.width, height: h)
        case .topLeft:     return NSRect(x: v.minX, y: v.minY + h, width: w, height: v.height - h)
        case .topRight:    return NSRect(x: v.minX + w, y: v.minY + h, width: v.width - w, height: v.height - h)
        case .bottomLeft:  return NSRect(x: v.minX, y: v.minY, width: w, height: h)
        case .bottomRight: return NSRect(x: v.minX + w, y: v.minY, width: v.width - w, height: h)
        case .maximize:    return v
        }
    }

    /// Which zone the cursor (Cocoa coords) is in while dragging, if any.
    static func at(_ p: NSPoint, on screen: NSScreen) -> Zone? {
        let f = screen.frame, edge: CGFloat = 4, corner: CGFloat = 120
        // An edge only counts if no other screen continues past it.
        func open(_ dx: CGFloat, _ dy: CGFloat) -> Bool {
            let q = NSPoint(x: p.x + dx, y: p.y + dy)
            return !NSScreen.screens.contains { $0 != screen && NSMouseInRect(q, $0.frame, false) }
        }
        let l = p.x <= f.minX + edge && open(-edge - 2, 0)
        let r = p.x >= f.maxX - edge - 1 && open(edge + 2, 0)
        let t = p.y >= f.maxY - edge - 1 && open(0, edge + 2)
        let b = p.y <= f.minY + edge && open(0, -edge - 2)
        let nearTop = p.y >= f.maxY - corner, nearBottom = p.y <= f.minY + corner
        let nearLeft = p.x <= f.minX + corner, nearRight = p.x >= f.maxX - corner
        if l { return nearTop ? .topLeft : nearBottom ? .bottomLeft : .left }
        if r { return nearTop ? .topRight : nearBottom ? .bottomRight : .right }
        if t { return nearLeft ? .topLeft : nearRight ? .topRight : .maximize }
        if b { return nearLeft ? .bottomLeft : nearRight ? .bottomRight : nil }
        return nil
    }
}

// MARK: - Accessibility helpers

enum AX {
    static let system = AXUIElementCreateSystemWide()

    /// Cocoa (bottom-left) ↔ AX / Quartz (top-left of primary screen) — the flip is symmetric.
    static func flip(_ r: NSRect) -> CGRect {
        let h = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height)
    }

    static func attr<T>(_ e: AXUIElement, _ name: String) -> T? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success else { return nil }
        return v as? T
    }

    static func window(at quartzPoint: CGPoint) -> AXUIElement? {
        var el: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(quartzPoint.x), Float(quartzPoint.y), &el) == .success,
              let el else { return nil }
        if (attr(el, kAXRoleAttribute) as String?) == kAXWindowRole { return el }
        return attr(el, kAXWindowAttribute)
    }

    static func focusedWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return attr(AXUIElementCreateApplication(app.processIdentifier), kAXFocusedWindowAttribute)
    }

    static func position(_ w: AXUIElement) -> CGPoint? {
        guard let v: AXValue = attr(w, kAXPositionAttribute) else { return nil }
        var p = CGPoint.zero; AXValueGetValue(v, .cgPoint, &p); return p
    }

    static func size(_ w: AXUIElement) -> CGSize? {
        guard let v: AXValue = attr(w, kAXSizeAttribute) else { return nil }
        var s = CGSize.zero; AXValueGetValue(v, .cgSize, &s); return s
    }

    /// Quartz-coordinate frame.
    static func frame(_ w: AXUIElement) -> CGRect? {
        guard let p = position(w), let s = size(w) else { return nil }
        return CGRect(origin: p, size: s)
    }

    static func setFrame(_ w: AXUIElement, _ r: CGRect) {
        var p = r.origin, s = r.size
        let pv = AXValueCreate(.cgPoint, &p)!, sv = AXValueCreate(.cgSize, &s)!
        // size → position → size: macOS clamps whichever is set first to keep the window on screen.
        AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, sv)
        AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, pv)
        AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, sv)
    }
}

// MARK: - Menu-bar icon: follows how you drag

enum Icon {
    static let idle = "rectangle.split.2x2"
    static var set: (String) -> Void = { _ in }
    /// Last snapped layout (shown when not dragging).
    static var last: String = UserDefaults.standard.string(forKey: "lastZoneIcon") ?? idle {
        didSet { UserDefaults.standard.set(last, forKey: "lastZoneIcon"); set(last) }
    }
}

// MARK: - Snapping

final class Snapper {
    static let shared = Snapper()
    private var previous: [CFHashCode: (original: CGRect, placed: CGRect)] = [:]   // for Restore

    func screen(for quartzFrame: CGRect) -> NSScreen {
        let cocoa = AX.flip(quartzFrame)                  // flip is its own inverse
        let center = NSPoint(x: cocoa.midX, y: cocoa.midY)
        return NSScreen.screens.first { NSMouseInRect(center, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    func snap(_ w: AXUIElement, to zone: Zone, on screen: NSScreen? = nil) {
        guard let cur = AX.frame(w) else { return }
        let scr = screen ?? self.screen(for: cur)
        let key = CFHash(w)
        // Keep the original frame across snap→snap; start over if the window was moved since.
        let original = previous[key].map { close($0.placed, cur) ? $0.original : cur } ?? cur
        AX.setFrame(w, AX.flip(zone.rect(in: scr.visibleFrame)))
        Icon.last = zone.symbol
        previous[key] = (original, AX.frame(w) ?? cur)
    }

    func restore(_ w: AXUIElement) {
        guard let e = previous.removeValue(forKey: CFHash(w)), let cur = AX.frame(w), close(e.placed, cur) else { return }
        AX.setFrame(w, e.original)
        Icon.last = Icon.idle
    }

    private func close(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 4 && abs(a.minY - b.minY) < 4 && abs(a.width - b.width) < 4 && abs(a.height - b.height) < 4
    }

    /// Forget the saved frame once the user moves a snapped window themselves.
    func forget(_ w: AXUIElement) { previous.removeValue(forKey: CFHash(w)) }
}

// MARK: - Preview overlay

final class Overlay {
    private let panel: NSPanel
    private var shownZone: Zone?

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        let v = NSView()
        v.wantsLayer = true
        v.layer?.cornerRadius = 14
        v.layer?.borderWidth = 2
        v.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.22).cgColor
        v.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.7).cgColor
        panel.contentView = v
    }

    func show(_ zone: Zone, on screen: NSScreen) {
        guard zone != shownZone || !panel.isVisible else { return }
        shownZone = zone
        let target = zone.rect(in: screen.visibleFrame).insetBy(dx: 6, dy: 6)
        if !panel.isVisible {
            let p = NSEvent.mouseLocation
            panel.setFrame(NSRect(x: p.x - 20, y: p.y - 20, width: 40, height: 40), display: false)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { c in
            c.duration = 0.15
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        shownZone = nil
        NSAnimationContext.runAnimationGroup({ c in
            c.duration = 0.1
            panel.animator().alphaValue = 0
        }, completionHandler: { [panel] in if panel.alphaValue == 0 { panel.orderOut(nil) } })
    }
}

// MARK: - Drag watcher

final class DragWatcher {
    private var monitors: [Any] = []
    private let overlay = Overlay()
    private var window: AXUIElement?
    private var startPos: CGPoint?
    private var moving = false
    private var zone: Zone?
    private var zoneScreen: NSScreen?

    func start() {
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] e in self?.down(e) } as Any)
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in self?.dragged() } as Any)
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in self?.up() } as Any)
    }

    private func down(_ e: NSEvent) {
        reset()
        guard let loc = e.cgEvent?.location, let w = AX.window(at: loc) else { return }
        window = w
        startPos = AX.position(w)
    }

    private func dragged() {
        guard let w = window else { return }
        if !moving {
            // Only a title-bar drag moves the window; text selection, resizing etc. don't.
            guard let start = startPos, let now = AX.position(w), now != start,
                  (AX.size(w)?.width ?? 0) > 0 else { return }
            moving = true
            Snapper.shared.forget(w)
        }
        let p = NSEvent.mouseLocation
        guard let scr = NSScreen.screens.first(where: { NSMouseInRect(p, $0.frame, false) }),
              let z = Zone.at(p, on: scr) else { zone = nil; overlay.hide(); Icon.set(Icon.last); return }
        zone = z; zoneScreen = scr
        Icon.set(z.symbol)
        overlay.show(z, on: scr)
    }

    private func up() {
        if moving, let w = window, let z = zone {
            // Let the app finish its own drag first, then place the window.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [scr = zoneScreen] in
                Snapper.shared.snap(w, to: z, on: scr)
            }
        }
        else { Icon.set(Icon.last) }
        overlay.hide()
        reset()
    }

    private func reset() { window = nil; startPos = nil; moving = false; zone = nil; zoneScreen = nil }
}

// MARK: - Menu actions (act on the front window)

enum Actions {
    static func snapFront(_ z: Zone) { guard let w = AX.focusedWindow() else { NSSound.beep(); return }; Snapper.shared.snap(w, to: z) }
    static func restoreFront() { guard let w = AX.focusedWindow() else { NSSound.beep(); return }; Snapper.shared.restore(w) }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var item: NSStatusItem!
    private let watcher = DragWatcher()
    private var trustItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private func showIcon(_ symbol: String) {
        item.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Mac Snap")
            ?? NSImage(systemSymbolName: Icon.idle, accessibilityDescription: "Mac Snap")
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        AXUIElementSetMessagingTimeout(AX.system, 0.3)
        let trusted = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        if !trusted { NSLog("Mac Snap: waiting for Accessibility permission") }

        // On a notched MacBook a full menu bar hides new icons behind the notch — start near the clock instead.
        // (⌘-drag the icon to move it; macOS remembers the spot.)
        let posKey = "NSStatusItem Preferred Position MacSnap"
        if UserDefaults.standard.object(forKey: posKey) == nil { UserDefaults.standard.set(230, forKey: posKey) }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "MacSnap"
        Icon.set = { [weak self] in self?.showIcon($0) }
        showIcon(Icon.last)
        let menu = NSMenu()
        menu.delegate = self
        trustItem = NSMenuItem(title: "", action: #selector(openAXSettings), keyEquivalent: "")
        menu.addItem(trustItem)
        menu.addItem(.separator())
        for z in [Zone.left, .right, .top, .bottom, .topLeft, .topRight, .bottomLeft, .bottomRight, .maximize] {
            if z == .topLeft || z == .maximize { menu.addItem(.separator()) }
            let mi = NSMenuItem(title: z.title, action: #selector(snapFromMenu(_:)), keyEquivalent: "")
            mi.representedObject = z.rawValue
            mi.target = self
            menu.addItem(mi)
        }
        let r = NSMenuItem(title: "Restore", action: #selector(restoreFromMenu), keyEquivalent: "")
        r.target = self
        menu.addItem(r)
        menu.addItem(.separator())
        loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)
        menu.addItem(NSMenuItem(title: "Quit Mac Snap", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
        item.menu = menu

        watcher.start()
        // Launch at login is on unless turned off; re-registering also follows the app if it was renamed/moved.
        if UserDefaults.standard.object(forKey: "launchAtLogin") as? Bool ?? true { try? SMAppService.mainApp.register() }
    }

    func menuWillOpen(_ menu: NSMenu) {
        let ok = AXIsProcessTrusted()
        trustItem.title = ok ? "✓ Accessibility allowed" : "⚠︎ Allow Accessibility access…"
        trustItem.target = ok ? nil : self
        trustItem.action = ok ? nil : #selector(openAXSettings)
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc func snapFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let z = Zone(rawValue: raw) else { return }
        Actions.snapFront(z)
    }
    @objc func restoreFromMenu() { Actions.restoreFront() }

    @objc func openAXSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc func toggleLogin() {
        let s = SMAppService.mainApp
        let on = s.status != .enabled
        UserDefaults.standard.set(on, forKey: "launchAtLogin")
        do { if on { try s.register() } else { try s.unregister() } }
        catch { NSLog("Mac Snap: login item: \(error)") }
    }
}

@main
struct Main {
    static func main() {
        let app = NSApplication.shared
        let d = AppDelegate()
        app.delegate = d
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

// Mac Snap — drag a window to a screen edge or corner to snap it (like Magnet / Windows Snap).
//   left / right edge  → half        corners → quarter        top edge → maximize
// No keyboard shortcuts and no window commands in the menu — dragging is the whole app. Menu → Help explains it.
import AppKit
import ApplicationServices
import ServiceManagement

// MARK: - Zones

enum Zone: String, CaseIterable {
    case left, right, topLeft, topRight, bottomLeft, bottomRight, maximize

    var title: String {
        switch self {
        case .left: "Left half"; case .right: "Right half"
        case .topLeft: "Top-left quarter"; case .topRight: "Top-right quarter"; case .bottomLeft: "Bottom-left quarter"; case .bottomRight: "Bottom-right quarter"
        case .maximize: "Maximize"
        }
    }

    /// Menu-bar icon showing this layout.
    var symbol: String {
        switch self {
        case .left: "rectangle.lefthalf.inset.filled"; case .right: "rectangle.righthalf.inset.filled"
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

    func snap(_ w: AXUIElement, to zone: Zone, on screen: NSScreen) {
        AX.setFrame(w, AX.flip(zone.rect(in: screen.visibleFrame)))
        Icon.last = zone.symbol
    }
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [scr = zoneScreen!] in
                Snapper.shared.snap(w, to: z, on: scr)
            }
        }
        else { Icon.set(Icon.last) }
        overlay.hide()
        reset()
    }

    private func reset() { window = nil; startPos = nil; moving = false; zone = nil; zoneScreen = nil }
}

// MARK: - Help window

enum HelpWindow {
    /// (zone, where the mouse goes in 0…1 screen coords with y up, what to say)
    static let cards: [(Zone, CGPoint, String)] = [
        (.left, CGPoint(x: 0, y: 0.5), "Left edge"), (.right, CGPoint(x: 1, y: 0.5), "Right edge"),
        (.maximize, CGPoint(x: 0.5, y: 1), "Top edge"), (.topLeft, CGPoint(x: 0, y: 1), "Top-left corner"),
        (.topRight, CGPoint(x: 1, y: 1), "Top-right corner"), (.bottomLeft, CGPoint(x: 0, y: 0), "Bottom-left corner"),
        (.bottomRight, CGPoint(x: 1, y: 0), "Bottom-right corner"),
    ]

    static func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: text)
        l.font = .systemFont(ofSize: size, weight: weight); l.textColor = color
        return l
    }

    static func make() -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 600),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Mac Snap Help"
        w.isReleasedWhenClosed = false

        let grid = NSGridView(numberOfColumns: 4, rows: 0)
        grid.rowSpacing = 16; grid.columnSpacing = 18
        var row: [NSView] = []
        for (zone, cursor, place) in cards {
            let card = NSStackView(views: [MiniScreen(zone: zone, cursor: cursor),
                                           label(place, size: 12, weight: .semibold),
                                           label("→ " + zone.title.replacingOccurrences(of: "Maximize", with: "Full screen"), size: 11, color: .secondaryLabelColor)])
            card.orientation = .vertical; card.alignment = .centerX; card.spacing = 4
            row.append(card)
            if row.count == 4 { grid.addRow(with: row); row = [] }
        }
        if !row.isEmpty { grid.addRow(with: row) }

        let behavior = label("""
        •  Grab a window by its title bar and drag it.
        •  Push the mouse pointer right against the edge or into a corner of the screen.
        •  A blue box shows where the window will go. Let go of the mouse to snap it there.
        •  Changed your mind? Move away from the edge before letting go — nothing happens.
        •  To unsnap, just drag the window away and resize it as usual.
        •  The menu-bar icon shows the layout you are dragging to, then keeps showing the last one you used.
        •  Works on every screen. On an edge between two screens the mouse passes through, so it doesn't snap there.
        •  Mac Snap needs Accessibility access (System Settings › Privacy & Security › Accessibility).
        """, size: 13)
        behavior.preferredMaxLayoutWidth = 580

        let stack = NSStackView(views: [label("Drag a window to an edge or corner", size: 20, weight: .bold), grid,
                                       label("How it works", size: 15, weight: .semibold), behavior])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 30, bottom: 24, right: 30)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor), stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor), stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        w.contentView = content
        return w
    }
}

/// A tiny screen: the snapped area filled in, and a pointer at the edge you drag to.
final class MiniScreen: NSView {
    let zone: Zone, cursor: CGPoint
    init(zone: Zone, cursor: CGPoint) {
        self.zone = zone; self.cursor = cursor
        super.init(frame: NSRect(x: 0, y: 0, width: 128, height: 84))
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 128).isActive = true
        heightAnchor.constraint(equalToConstant: 84).isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirty: NSRect) {
        let scr = bounds.insetBy(dx: 6, dy: 6)
        let body = NSBezierPath(roundedRect: scr, xRadius: 6, yRadius: 6)
        NSColor.windowBackgroundColor.blended(withFraction: 0.08, of: .labelColor)?.setFill(); body.fill()
        NSColor.separatorColor.setStroke(); body.lineWidth = 1; body.stroke()
        // menu bar
        let bar = NSRect(x: scr.minX, y: scr.maxY - 7, width: scr.width, height: 7)
        NSGraphicsContext.saveGraphicsState(); body.addClip()
        NSColor.labelColor.withAlphaComponent(0.12).setFill(); bar.fill()
        NSGraphicsContext.restoreGraphicsState()
        // snapped area
        let usable = NSRect(x: scr.minX, y: scr.minY, width: scr.width, height: scr.height - 7)
        let target = zone.rect(in: usable).insetBy(dx: 3, dy: 3)
        let fill = NSBezierPath(roundedRect: target, xRadius: 4, yRadius: 4)
        NSColor.controlAccentColor.withAlphaComponent(0.35).setFill(); fill.fill()
        NSColor.controlAccentColor.setStroke(); fill.lineWidth = 1.5; fill.stroke()
        // pointer at the edge
        let p = NSPoint(x: scr.minX + cursor.x * scr.width, y: scr.minY + cursor.y * scr.height)
        let dot = NSBezierPath(ovalIn: NSRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10))
        NSColor.systemOrange.setFill(); dot.fill()
        NSColor.white.setStroke(); dot.lineWidth = 1.5; dot.stroke()
    }
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
        let help = NSMenuItem(title: "Help — How to Snap…", action: #selector(showHelp), keyEquivalent: "")
        help.target = self
        menu.addItem(help)
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

    private var helpWindow: NSWindow?
    @objc func showHelp() {
        if helpWindow == nil { helpWindow = HelpWindow.make() }
        NSApp.activate(ignoringOtherApps: true)
        helpWindow?.center()
        helpWindow?.makeKeyAndOrderFront(nil)
    }

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

// Q-Dock — a floating, pinnable dock for macOS with a copy on every screen.
import AppKit
import Carbon
import ApplicationServices
import Combine
import QuickLookThumbnailing
import ServiceManagement
import SwiftUI

let kPad: CGFloat = 10
let kDot: CGFloat = 6
let kHandle: CGFloat = 14
let kMargin: CGFloat = 4
let kSnap: CGFloat = 60
let kMagnify: CGFloat = 1.18
let kNeighbor: CGFloat = 1.07

// MARK: - Model

enum Edge: String, Codable { case left, right, top, bottom, free }
enum StackStyle: String { case fan, grid, folder }
enum StackSort: String { case dateAdded, dateModified, dateCreated, name, kind }

struct Placement: Codable, Equatable {
    var edge: Edge = .left
    var fx: CGFloat = 0.5   // dock center, as a fraction of the screen's visible frame
    var fy: CGFloat = 0.5
    var vertical = true     // orientation when floating
    var isVertical: Bool {
        switch edge {
        case .left, .right: return true
        case .top, .bottom: return false
        case .free: return vertical
        }
    }
}

final class Store {
    static let shared = Store()
    static let changed = Notification.Name("QDockStoreChanged")
    private let d = UserDefaults.standard

    var items: [URL] {
        get {
            if let paths = d.stringArray(forKey: "items") { return paths.map { URL(fileURLWithPath: $0) } }
            return systemDockItems()
        }
        set { d.set(newValue.map(\.path), forKey: "items"); post() }
    }
    private func bool(_ key: String, _ def: Bool) -> Bool { d.object(forKey: key) as? Bool ?? def }
    private func setBool(_ key: String, _ v: Bool) { d.set(v, forKey: key); post() }

    var iconSize: CGFloat {
        get { let v = d.double(forKey: "iconSize"); return v > 0 ? v : 32 }
        set { d.set(Double(newValue), forKey: "iconSize"); post() }
    }
    var spacing: CGFloat {
        get { d.object(forKey: "spacing") as? Double ?? 0 }
        set { d.set(Double(newValue), forKey: "spacing"); post() }
    }
    var allScreens: Bool { get { bool("allScreens", true) } set { setBool("allScreens", newValue) } }
    var syncPositions: Bool { get { bool("syncPositions", false) } set { setBool("syncPositions", newValue) } }
    var alwaysOnTop: Bool { get { bool("alwaysOnTop", true) } set { setBool("alwaysOnTop", newValue) } }
    var showTrash: Bool { get { bool("showTrash", true) } set { setBool("showTrash", newValue) } }
    var showRunning: Bool { get { bool("showRunning", true) } set { setBool("showRunning", newValue) } }
    var locked: Bool { get { bool("locked", true) } set { setBool("locked", newValue) } }
    var dockMode: Bool { get { bool("dockMode", true) } set { setBool("dockMode", newValue) } }
    var hideSystemDock: Bool { get { bool("hideSystemDock", false) } set { setBool("hideSystemDock", newValue) } }
    var restoreSystemDockOnQuit: Bool {
        get { bool("restoreSystemDockOnQuit", true) }
        set { setBool("restoreSystemDockOnQuit", newValue) }
    }
    var askedSystemDock: Bool { get { bool("askedSystemDock", false) } set { d.set(newValue, forKey: "askedSystemDock") } }

    private var placements: [String: Placement] {
        get { d.data(forKey: "placements").flatMap { try? JSONDecoder().decode([String: Placement].self, from: $0) } ?? [:] }
        set { d.set(try? JSONEncoder().encode(newValue), forKey: "placements") }
    }
    func placement(for id: String) -> Placement {
        let p = placements
        return syncPositions ? (p["*"] ?? defaultPlacement(for: nil)) : (p[id] ?? defaultPlacement(for: id))
    }
    /// Main screen: top edge, centered. Other screens: bottom edge, toward the right.
    private func defaultPlacement(for id: String?) -> Placement {
        if id == nil || id == NSScreen.screens.first?.stableID {
            return Placement(edge: .top, fx: 0.5, fy: 1, vertical: false)
        }
        return Placement(edge: .bottom, fx: 0.88, fy: 0, vertical: false)
    }
    private var autoHideMap: [String: Bool] {
        get { d.dictionary(forKey: "autoHide") as? [String: Bool] ?? [:] }
        set { d.set(newValue, forKey: "autoHide") }
    }
    func autoHide(for id: String) -> Bool {
        let m = autoHideMap
        return syncPositions ? (m["*"] ?? false) : (m[id] ?? m["*"] ?? false)
    }
    func setAutoHide(_ v: Bool, for ids: [String]) {
        var m = autoHideMap
        if syncPositions { m["*"] = v } else { ids.forEach { m[$0] = v } }
        autoHideMap = m
        post()
    }

    func setPlacement(_ pl: Placement, for ids: [String]) {
        var p = placements
        if syncPositions { p["*"] = pl } else { ids.forEach { p[$0] = pl } }
        placements = p
        post()
    }

    private func folderSetting(_ key: String, _ url: URL) -> String? { (d.dictionary(forKey: key) as? [String: String])?[url.path] }
    private func setFolderSetting(_ key: String, _ url: URL, _ v: String) {
        var m = (d.dictionary(forKey: key) as? [String: String]) ?? [:]
        m[url.path] = v
        d.set(m, forKey: key)
    }
    func stackStyle(for u: URL) -> StackStyle { folderSetting("stackStyles", u).flatMap(StackStyle.init) ?? .grid }
    func setStackStyle(_ s: StackStyle, for u: URL) { setFolderSetting("stackStyles", u, s.rawValue) }
    func stackSort(for u: URL) -> StackSort { folderSetting("stackSorts", u).flatMap(StackSort.init) ?? .dateAdded }
    func setStackSort(_ s: StackSort, for u: URL) { setFolderSetting("stackSorts", u, s.rawValue) }

    func add(_ urls: [URL], at index: Int? = nil) {
        var it = items
        let new = urls.filter { u in !it.contains { $0.path == u.path } }
        guard !new.isEmpty else { return }
        it.insert(contentsOf: new, at: min(index ?? it.count, it.count))
        items = it
    }
    func remove(_ url: URL) { items = items.filter { $0.path != url.path } }
    func move(from: Int, to: Int) {
        var it = items
        guard from != to, it.indices.contains(from) else { return }
        let x = it.remove(at: from)
        it.insert(x, at: min(to, it.count))
        items = it
    }
    func post() { NotificationCenter.default.post(name: Store.changed, object: nil) }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
    var stableID: String {
        if let u = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() {
            return CFUUIDCreateString(nil, u) as String
        }
        return "\(displayID)"
    }
}

func canonicalPath(_ url: URL) -> String { url.resolvingSymlinksInPath().standardizedFileURL.path }

func displayName(_ url: URL) -> String {
    let n = FileManager.default.displayName(atPath: url.path)
    return n.hasSuffix(".app") ? String(n.dropLast(4)) : n
}

let trashURL = FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first
    ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")

func trashIsFull() -> Bool {
    let items = (try? FileManager.default.contentsOfDirectory(atPath: trashURL.path)) ?? []
    return items.contains { $0 != ".DS_Store" && $0 != ".localized" }
}

func trashImage(full: Bool) -> NSImage {
    NSImage(named: full ? NSImage.trashFullName : NSImage.trashEmptyName) ?? NSWorkspace.shared.icon(forFile: trashURL.path)
}

func emptyTrash() {
    NSApp.activate(ignoringOtherApps: true)
    let a = NSAlert()
    a.messageText = "Are you sure you want to permanently erase the items in the Trash?"
    a.informativeText = "You can't undo this action."
    a.addButton(withTitle: "Empty Trash")
    a.addButton(withTitle: "Cancel")
    guard a.runModal() == .alertFirstButtonReturn else { return }
    var err: NSDictionary?
    NSAppleScript(source: "tell application \"Finder\" to empty trash")?.executeAndReturnError(&err)
}

/// A transform that scales by (sx, sy) around point `p` (in the layer's bounds), then offsets by (dx, dy).
func scaleAbout(_ layer: CALayer, _ p: CGPoint, sx: CGFloat, sy: CGFloat, dx: CGFloat = 0, dy: CGFloat = 0) -> CATransform3D {
    let c = CGPoint(x: p.x - layer.anchorPoint.x * layer.bounds.width, y: p.y - layer.anchorPoint.y * layer.bounds.height)
    var m = CATransform3DMakeTranslation(c.x + dx, c.y + dy, 0)
    m = CATransform3DScale(m, sx, sy, 1)
    return CATransform3DTranslate(m, -c.x, -c.y, 0)
}

func aspectFit(_ size: NSSize, in r: NSRect) -> NSRect {
    guard size.width > 0, size.height > 0 else { return r }
    let k = min(r.width / size.width, r.height / size.height)
    let w = size.width * k, h = size.height * k
    return NSRect(x: r.midX - w / 2, y: r.midY - h / 2, width: w, height: h)
}

// MARK: - Menu helper

final class ActionItem: NSMenuItem {
    private let handler: () -> Void
    init(_ title: String, checked: Bool = false, enabled: Bool = true, key: String = "", _ handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: enabled ? #selector(fire) : nil, keyEquivalent: key)
        target = self
        state = checked ? .on : .off
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func fire() { handler() }
}

func submenuItem(_ title: String, _ menu: NSMenu) -> NSMenuItem {
    let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    i.submenu = menu
    return i
}

// MARK: - Hover label

final class HoverLabel {
    static let shared = HoverLabel()
    static let maxTextWidth: CGFloat = 280
    private let panel: NSPanel
    private let field = NSTextField(labelWithString: "")

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .popUpMenu
        panel.ignoresMouseEvents = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let fx = NSVisualEffectView()
        fx.material = .toolTip
        fx.state = .active
        fx.blendingMode = .behindWindow
        fx.maskImage = roundedMask(12)
        field.font = .systemFont(ofSize: 13, weight: .medium)
        field.textColor = .labelColor
        field.lineBreakMode = .byTruncatingTail
        fx.addSubview(field)
        panel.contentView = fx
    }

    func show(_ v: IconView) {
        guard let r = v.screenIconRect, let screen = v.window?.screen else { return }
        field.stringValue = v.displayName
        // Let the text field size itself so its internal cell padding is included; cap at the max width.
        field.sizeToFit()
        let fit = field.frame.size
        let textW = min(ceil(fit.width) + 2, HoverLabel.maxTextWidth)
        let size = NSSize(width: textW + 20, height: 24)
        field.frame = NSRect(x: 10, y: (size.height - fit.height) / 2, width: textW, height: fit.height)
        let gap = v.s * (kMagnify - 1) + 8
        var o: NSPoint
        switch v.dotSide {
        case .bottom: o = NSPoint(x: r.midX - size.width / 2, y: r.maxY + gap)
        case .top: o = NSPoint(x: r.midX - size.width / 2, y: r.minY - gap - size.height)
        case .left: o = NSPoint(x: r.maxX + gap, y: r.midY - size.height / 2)
        default: o = NSPoint(x: r.minX - gap - size.width, y: r.midY - size.height / 2)
        }
        let f = screen.frame
        o.x = max(f.minX + 2, min(o.x, f.maxX - size.width - 2))
        o.y = max(f.minY + 2, min(o.y, f.maxY - size.height - 2))
        panel.setFrame(NSRect(origin: o, size: size), display: true)
        panel.orderFrontRegardless()
    }

    func hide() { panel.orderOut(nil) }
}

// MARK: - Dock icon

final class IconView: NSView {
    enum Kind { case item, running, trash }
    let url: URL
    let kind: Kind
    let s: CGFloat
    let dotSide: Edge
    let isFolder: Bool
    weak var dock: DockView?
    private var image: NSImage
    private let imageLayer = CALayer()
    private(set) var magnification: CGFloat = 1
    var running = false { didSet { if running != oldValue { needsDisplay = true } } }
    var dimmed = false { didSet { alphaValue = dimmed ? 0.3 : 1 } }

    init(url: URL, kind: Kind = .item, image: NSImage? = nil, size: CGFloat, dotSide: Edge) {
        self.url = url
        self.kind = kind
        self.s = size
        self.dotSide = dotSide
        self.image = image ?? NSWorkspace.shared.icon(forFile: url.path)
        let rv = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        isFolder = kind == .item && (rv?.isDirectory ?? false) && !(rv?.isPackage ?? false)
        super.init(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        wantsLayer = true
        clipsToBounds = false
        imageLayer.contentsGravity = .resizeAspect
        imageLayer.anchorPoint = anchor
        layer?.addSublayer(imageLayer)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    required init?(coder: NSCoder) { fatalError() }

    var displayName: String { kind == .trash ? "Trash" : QDock.displayName(url) }
    var runningApp: NSRunningApplication? {
        let p = canonicalPath(url)
        return NSWorkspace.shared.runningApplications.first { $0.bundleURL.map(canonicalPath) == p }
    }
    var iconRect: NSRect {
        switch dotSide {
        case .bottom: return NSRect(x: 0, y: kDot, width: s, height: s)
        case .left: return NSRect(x: kDot, y: 0, width: s, height: s)
        default: return NSRect(x: 0, y: 0, width: s, height: s)
        }
    }
    var screenIconRect: NSRect? {
        guard let window else { return nil }
        return window.convertToScreen(convert(iconRect, to: nil))
    }
    private var anchor: CGPoint {
        switch dotSide {
        case .bottom: return CGPoint(x: 0.5, y: 0)
        case .top: return CGPoint(x: 0.5, y: 1)
        case .left: return CGPoint(x: 0, y: 0.5)
        default: return CGPoint(x: 1, y: 0.5)
        }
    }
    private var dotCenter: NSPoint {
        switch dotSide {
        case .bottom: return NSPoint(x: s / 2, y: kDot / 2 - 0.5)
        case .top: return NSPoint(x: s / 2, y: s + kDot / 2 + 0.5)
        case .left: return NSPoint(x: kDot / 2 - 0.5, y: s / 2)
        default: return NSPoint(x: s + kDot / 2 + 0.5, y: s / 2)
        }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let t = imageLayer.transform
        imageLayer.transform = CATransform3DIdentity
        imageLayer.frame = iconRect.insetBy(dx: s * 0.04, dy: s * 0.04)
        imageLayer.transform = t
        CATransaction.commit()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateImageContents()
    }

    private func updateImageContents() {
        let scale = window?.backingScaleFactor ?? 2
        imageLayer.contentsScale = image.recommendedLayerContentsScale(scale)
        imageLayer.contents = image.layerContents(forContentsScale: imageLayer.contentsScale)
    }

    func setImage(_ img: NSImage) {
        image = img
        updateImageContents()
    }

    private func scale(main: CGFloat, cross: CGFloat) -> CATransform3D {
        (dotSide == .left || dotSide == .right) ? CATransform3DMakeScale(cross, main, 1) : CATransform3DMakeScale(main, cross, 1)
    }

    /// Springs the icon to `m`; `genie` adds a quick stretch-away-from-the-edge before settling.
    func setMagnification(_ m: CGFloat, genie: Bool) {
        guard m != magnification else { return }
        magnification = m
        let from = imageLayer.presentation()?.transform ?? imageLayer.transform
        let to = CATransform3DMakeScale(m, m, 1)
        let anim: CAAnimation
        if genie {
            let k = CAKeyframeAnimation(keyPath: "transform")
            k.values = [from, scale(main: 1.04, cross: 1.28), scale(main: 1.22, cross: 1.12), to].map { NSValue(caTransform3D: $0) }
            k.keyTimes = [0, 0.35, 0.7, 1]
            k.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeInEaseOut),
                                 CAMediaTimingFunction(name: .easeInEaseOut)]
            k.duration = 0.3
            anim = k
        } else {
            let sp = CASpringAnimation(keyPath: "transform")
            sp.fromValue = NSValue(caTransform3D: from)
            sp.toValue = NSValue(caTransform3D: to)
            sp.mass = 0.6
            sp.stiffness = 260
            sp.damping = 14
            sp.duration = sp.settlingDuration
            anim = sp
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.transform = to
        imageLayer.add(anim, forKey: "magnify")
        CATransaction.commit()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseEntered(with e: NSEvent) { dock?.hover(self, inside: true) }
    override func mouseExited(with e: NSEvent) { dock?.hover(self, inside: false) }

    override func draw(_ dirtyRect: NSRect) {
        if running {
            NSColor.labelColor.withAlphaComponent(0.8).setFill()
            let c = dotCenter
            NSBezierPath(ovalIn: NSRect(x: c.x - 2, y: c.y - 2, width: 4, height: 4)).fill()
        }
    }

    func open(event: NSEvent? = nil) {
        if kind == .trash {
            NSWorkspace.shared.open(trashURL)
        } else if isFolder && Store.shared.stackStyle(for: url) != .folder {
            StackController.shared.toggle(self, event: event)
        } else if kind == .running || url.pathExtension == "app" {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    override func mouseDown(with e: NSEvent) {
        if e.modifierFlags.contains(.control) { rightMouseDown(with: e); return }
        guard let dock, let window else { return }
        let start = dock.convert(e.locationInWindow, from: nil)
        var dragging = false
        while let ev = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let p = dock.convert(ev.locationInWindow, from: nil)
            if ev.type == .leftMouseUp {
                NSCursor.arrow.set()
                if dragging { dock.endDrag(self) } else { open(event: e) }
                return
            }
            if kind != .trash && !dragging && hypot(p.x - start.x, p.y - start.y) > 4 {
                dragging = true
                dock.beginDrag(self, at: start)
            }
            if dragging { dock.drag(self, to: p) }
        }
    }

    override func rightMouseDown(with e: NSEvent) {
        HoverLabel.shared.hide()
        let m = NSMenu()
        m.addItem(NSMenuItem(title: displayName, action: nil, keyEquivalent: ""))
        m.addItem(.separator())
        if kind == .trash {
            m.addItem(ActionItem("Open") { NSWorkspace.shared.open(trashURL) })
            m.addItem(ActionItem("Empty Trash…", enabled: trashIsFull()) { emptyTrash() })
        } else if kind == .running {
            let u = url
            m.addItem(ActionItem("Keep in Dock") { Store.shared.add([u]) })
            m.addItem(ActionItem("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([u]) })
            if let app = runningApp {
                m.addItem(.separator())
                m.addItem(ActionItem("Hide") { app.hide() })
                m.addItem(ActionItem("Quit") { app.terminate() })
                m.addItem(ActionItem("Force Quit") { app.forceTerminate() })
            }
        } else {
            let u = url
            if isFolder {
                m.addItem(ActionItem("Open in Finder") { NSWorkspace.shared.open(u) })
                let style = Store.shared.stackStyle(for: u)
                let styles = NSMenu()
                for (st, name) in [(StackStyle.fan, "Fan"), (.grid, "Grid"), (.folder, "Folder (open in Finder)")] {
                    styles.addItem(ActionItem(name, checked: style == st) { Store.shared.setStackStyle(st, for: u) })
                }
                m.addItem(submenuItem("Display As", styles))
                let sort = Store.shared.stackSort(for: u)
                let sorts = NSMenu()
                for (so, name) in [(StackSort.name, "Name"), (.dateAdded, "Date Added"), (.dateModified, "Date Modified"),
                                   (.dateCreated, "Date Created"), (.kind, "Kind")] {
                    sorts.addItem(ActionItem(name, checked: sort == so) { Store.shared.setStackSort(so, for: u) })
                }
                m.addItem(submenuItem("Sort By", sorts))
            } else {
                m.addItem(ActionItem("Open") { [weak self] in self?.open() })
            }
            m.addItem(ActionItem("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([u]) })
            if let app = runningApp {
                m.addItem(ActionItem("Hide") { app.hide() })
                m.addItem(ActionItem("Quit") { app.terminate() })
                m.addItem(ActionItem("Force Quit") { app.forceTerminate() })
            }
            m.addItem(.separator())
            m.addItem(ActionItem("Remove from Dock") { Store.shared.remove(u) })
        }
        m.addItem(.separator())
        m.addItem(submenuItem("Q-Dock", AppController.shared.dockMenu(screenID: dock?.dock?.screenID)))
        NSMenu.popUpContextMenu(m, with: e, for: self)
    }
}

// MARK: - Dock view

let kSep: CGFloat = 9

/// Moves (same volume) or copies `urls` into `folder`, the way Finder does; ⌥ forces a copy.
func dropFiles(_ urls: [URL], into folder: URL, copy: Bool) {
    let fm = FileManager.default
    DispatchQueue.global(qos: .userInitiated).async {
        var failures: [String] = []
        for u in urls {
            let parent = u.deletingLastPathComponent().standardizedFileURL.path
            if !copy && parent == folder.standardizedFileURL.path { continue }
            if folder.path == u.path || folder.path.hasPrefix(u.path + "/") { continue }
            let dest = uniqueDestination(in: folder, for: u.lastPathComponent)
            do {
                if copy { try fm.copyItem(at: u, to: dest) } else { try fm.moveItem(at: u, to: dest) }
            } catch {
                failures.append("\(u.lastPathComponent): \(error.localizedDescription)")
            }
        }
        guard !failures.isEmpty else { return }
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let a = NSAlert()
            a.messageText = "Some items couldn't be \(copy ? "copied" : "moved") to “\(displayName(folder))”"
            a.informativeText = failures.joined(separator: "\n")
            a.runModal()
        }
    }
}

func uniqueDestination(in folder: URL, for name: String) -> URL {
    var dest = folder.appendingPathComponent(name)
    let ext = (name as NSString).pathExtension
    let stem = (name as NSString).deletingPathExtension
    var n = 2
    while FileManager.default.fileExists(atPath: dest.path) {
        dest = folder.appendingPathComponent(ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)")
        n += 1
    }
    return dest
}

func sameVolume(_ a: URL, _ b: URL) -> Bool {
    let va = (try? a.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier as? NSObject
    let vb = (try? b.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier as? NSObject
    return va != nil && va == vb
}

final class DockView: NSView {
    weak var dock: Dock?
    private(set) var icons: [IconView] = []    // pinned
    private(set) var extras: [IconView] = []   // running but not pinned
    private(set) var trash: IconView?
    private var s: CGFloat = 48
    private var sp: CGFloat = 6
    private var locked = false
    private var vertical = true
    private var edge: Edge = .left
    private var maxMain: CGFloat = 1000
    private var slotFrames: [NSRect] = []   // pinned slots (or the empty placeholder)
    private var tailFrames: [NSRect] = []   // running apps, then trash
    private var separatorFrame: NSRect?
    private var lineCount = 1
    private var mainExtent: CGFloat = 0
    private var dragOrder: [IconView]?
    private var dragTarget = 0
    private var draggingRunning = false
    private var grab = NSPoint.zero
    private weak var hovered: IconView?

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init() {
        super.init(frame: .zero)
        clipsToBounds = false
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError() }

    private var base: CGFloat { locked ? kPad : kPad + kHandle + sp }
    private var cellCross: CGFloat { s + kDot }
    private var tail: [IconView] { extras + (trash.map { [$0] } ?? []) }
    private var allViews: [IconView] { icons + tail }
    private func main(_ p: NSPoint) -> CGFloat { vertical ? p.y : p.x }
    private func pt(_ main: CGFloat, _ cross: CGFloat) -> NSPoint { vertical ? NSPoint(x: cross, y: main) : NSPoint(x: main, y: cross) }
    private var crossLength: CGFloat { kPad * 2 + CGFloat(lineCount) * cellCross + CGFloat(lineCount - 1) * sp }
    /// The first line hugs the pinned edge; extra lines stack away from it.
    private func visualLine(_ line: Int) -> Int { (edge == .right || edge == .bottom) ? lineCount - 1 - line : line }

    var preferredSize: NSSize {
        vertical ? NSSize(width: crossLength, height: mainExtent) : NSSize(width: mainExtent, height: crossLength)
    }

    /// `maxLength` is the room available along the dock's main axis; icons wrap onto extra lines past it.
    func configure(items: [URL], running: [URL], size: CGFloat, spacing: CGFloat, locked: Bool, showTrash: Bool, trashFull: Bool,
                   vertical: Bool, edge: Edge, maxLength: CGFloat, runningPaths: Set<String>) {
        s = size
        sp = spacing
        self.locked = locked
        self.vertical = vertical
        self.edge = edge
        maxMain = maxLength
        hovered = nil
        allViews.forEach { $0.removeFromSuperview() }
        let side: Edge = vertical ? (edge == .right ? .right : .left) : (edge == .top ? .top : .bottom)
        let make = { (u: URL, kind: IconView.Kind, img: NSImage?) -> IconView in
            let v = IconView(url: u, kind: kind, image: img, size: size, dotSide: side)
            v.dock = self
            self.addSubview(v)
            return v
        }
        icons = items.map { make($0, .item, nil) }
        extras = running.map { make($0, .running, nil) }
        trash = showTrash ? make(trashURL, .trash, trashImage(full: trashFull)) : nil
        computeLayout()
        refreshRunning(runningPaths)
        layoutIcons(icons, animated: false, except: nil)
        for (v, f) in zip(tail, tailFrames) { v.frame = f }
        needsDisplay = true
    }

    /// Flow layout: pinned items (or placeholder) · separator · running apps · trash, wrapping onto new lines.
    private func computeLayout() {
        let pinnedCount = max(icons.count, 1)
        let hasSep = !tail.isEmpty
        var lens = Array(repeating: s, count: pinnedCount)
        if hasSep { lens.append(kSep) }
        lens += Array(repeating: s, count: tail.count)
        var raw: [(line: Int, main: CGFloat, len: CGFloat)] = []
        var line = 0, cur = base, extent = base
        for len in lens {
            if cur + len > maxMain - kPad && cur > base { line += 1; cur = base }
            raw.append((line, cur, len))
            extent = max(extent, cur + len)
            cur += len + sp
        }
        lineCount = line + 1
        mainExtent = extent + kPad
        let frames = raw.map { r -> NSRect in
            let c = kPad + CGFloat(visualLine(r.line)) * (cellCross + sp)
            return vertical ? NSRect(x: c, y: r.main, width: cellCross, height: r.len)
                            : NSRect(x: r.main, y: c, width: r.len, height: cellCross)
        }
        slotFrames = Array(frames[0..<pinnedCount])
        separatorFrame = hasSep ? frames[pinnedCount] : nil
        tailFrames = Array(frames[(pinnedCount + (hasSep ? 1 : 0))...])
    }

    func refreshRunning(_ running: Set<String>) {
        icons.forEach { $0.running = running.contains(canonicalPath($0.url)) }
        extras.forEach { $0.running = true }
    }

    private func layoutIcons(_ order: [IconView], animated: Bool, except: IconView?) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = animated ? 0.15 : 0
            for (i, v) in order.enumerated() where v !== except && i < slotFrames.count {
                if animated { v.animator().frame = slotFrames[i] } else { v.frame = slotFrames[i] }
            }
        }
    }

    private func nearestSlot(_ p: NSPoint) -> Int {
        slotFrames.indices.min { hypot(slotFrames[$0].midX - p.x, slotFrames[$0].midY - p.y) < hypot(slotFrames[$1].midX - p.x, slotFrames[$1].midY - p.y) } ?? 0
    }
    /// Where a dropped item would be inserted among the pinned items.
    private func insertionIndex(_ p: NSPoint) -> Int {
        guard !icons.isEmpty else { return 0 }
        let i = nearestSlot(p)
        return main(p) > main(NSPoint(x: slotFrames[i].midX, y: slotFrames[i].midY)) ? i + 1 : i
    }
    private func nearPinned(_ p: NSPoint) -> Bool {
        let f = slotFrames[nearestSlot(p)]
        return hypot(f.midX - p.x, f.midY - p.y) < s
    }

    private var placeholderRect: NSRect {
        let f = slotFrames.first ?? .zero
        return vertical ? NSRect(x: f.minX + kDot / 2, y: f.minY, width: s, height: s)
                        : NSRect(x: f.minX, y: f.minY + kDot / 2, width: s, height: s)
    }

    override func draw(_ dirtyRect: NSRect) {
        if !locked {
            NSColor.secondaryLabelColor.withAlphaComponent(0.6).setFill()
            let mid = kPad + cellCross / 2 + (edge == .right || edge == .bottom ? CGFloat(lineCount - 1) * (cellCross + sp) : 0)
            for a in [kPad + 4, kPad + 9] {
                for b in [mid - 6, mid, mid + 6] {
                    let c = pt(a, b)
                    NSBezierPath(ovalIn: NSRect(x: c.x - 1.25, y: c.y - 1.25, width: 2.5, height: 2.5)).fill()
                }
            }
        }
        if let r = separatorFrame {
            NSColor.labelColor.withAlphaComponent(0.25).setFill()
            let half = s * 0.4
            NSBezierPath(rect: vertical ? NSRect(x: r.midX - half, y: r.midY - 0.5, width: half * 2, height: 1)
                                        : NSRect(x: r.midX - 0.5, y: r.midY - half, width: 1, height: half * 2)).fill()
        }
        if icons.isEmpty {
            let r = placeholderRect.insetBy(dx: 4, dy: 4)
            let path = NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10)
            path.lineWidth = 1.5
            path.setLineDash([4, 3], count: 2, phase: 0)
            NSColor.secondaryLabelColor.setStroke()
            path.stroke()
            let plus = NSBezierPath()
            plus.move(to: NSPoint(x: r.midX - 6, y: r.midY)); plus.line(to: NSPoint(x: r.midX + 6, y: r.midY))
            plus.move(to: NSPoint(x: r.midX, y: r.midY - 6)); plus.line(to: NSPoint(x: r.midX, y: r.midY + 6))
            plus.lineWidth = 1.5
            plus.stroke()
        }
    }

    // Hover: instant name label + magnification

    func hover(_ v: IconView, inside: Bool) {
        guard dragOrder == nil && !draggingRunning else { return }
        if inside {
            hovered = v
            HoverLabel.shared.show(v)
        } else if hovered === v {
            hovered = nil
            HoverLabel.shared.hide()
        }
        applyMagnification()
    }

    private func applyMagnification() {
        let views = allViews
        let hi = hovered.flatMap { h in views.firstIndex { $0 === h } }
        let crossOf = { (v: IconView) in self.vertical ? v.frame.minX : v.frame.minY }
        for (i, v) in views.enumerated() {
            var m: CGFloat = 1
            if let hi {
                if i == hi { m = kMagnify } else if abs(i - hi) == 1 && crossOf(v) == crossOf(views[hi]) { m = kNeighbor }
            }
            v.setMagnification(m, genie: i == hi)
        }
    }

    // Reordering / drag-out-to-remove / drop-on-trash-to-remove / drag running app in to pin

    func beginDrag(_ v: IconView, at p: NSPoint) {
        hovered = nil
        HoverLabel.shared.hide()
        applyMagnification()
        grab = NSPoint(x: p.x - v.frame.minX, y: p.y - v.frame.minY)
        addSubview(v, positioned: .above, relativeTo: nil)
        if v.kind == .running {
            draggingRunning = true
            return
        }
        dragOrder = icons
        dragTarget = icons.firstIndex { $0 === v } ?? 0
    }

    private func overTrash(_ v: IconView) -> Bool {
        guard let trash else { return false }
        return trash.frame.contains(NSPoint(x: v.frame.midX, y: v.frame.midY))
    }

    func drag(_ v: IconView, to p: NSPoint) {
        v.setFrameOrigin(NSPoint(x: p.x - grab.x, y: p.y - grab.y))
        if draggingRunning { return }
        guard var order = dragOrder else { return }
        let onTrash = overTrash(v)
        v.dimmed = onTrash || !bounds.insetBy(dx: -40, dy: -40).contains(p)
        trash?.setMagnification(onTrash ? kMagnify : 1, genie: onTrash)
        (v.dimmed ? NSCursor.disappearingItem : NSCursor.arrow).set()
        let t = min(nearestSlot(NSPoint(x: v.frame.midX, y: v.frame.midY)), icons.count - 1)
        if t != dragTarget && !onTrash {
            order.removeAll { $0 === v }
            order.insert(v, at: t)
            dragOrder = order
            dragTarget = t
            layoutIcons(order, animated: true, except: v)
        }
    }

    func endDrag(_ v: IconView) {
        let c = NSPoint(x: v.frame.midX, y: v.frame.midY)
        if draggingRunning {
            draggingRunning = false
            if nearPinned(c) {
                Store.shared.add([v.url], at: insertionIndex(c))
            } else if let i = extras.firstIndex(where: { $0 === v }) {
                v.animator().frame = tailFrames[i]
            }
            return
        }
        guard let from = icons.firstIndex(where: { $0 === v }) else { return }
        dragOrder = nil
        trash?.setMagnification(1, genie: false)
        if v.dimmed { Store.shared.remove(v.url); return }
        if from == dragTarget {
            layoutIcons(icons, animated: true, except: nil)
        } else {
            Store.shared.move(from: from, to: dragTarget)
        }
    }

    // Moving the whole dock (grab the handle or any empty area) unless locked

    override func mouseDown(with e: NSEvent) {
        if e.modifierFlags.contains(.control) { rightMouseDown(with: e); return }
        if icons.isEmpty && placeholderRect.contains(convert(e.locationInWindow, from: nil)) {
            AppController.shared.addItems()
            return
        }
        guard !locked, let window else { return }
        let startMouse = NSEvent.mouseLocation
        let startOrigin = window.frame.origin
        var moved = false
        while let ev = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let m = NSEvent.mouseLocation
            if hypot(m.x - startMouse.x, m.y - startMouse.y) > 2 { moved = true }
            window.setFrameOrigin(NSPoint(x: startOrigin.x + m.x - startMouse.x, y: startOrigin.y + m.y - startMouse.y))
            if ev.type == .leftMouseUp { break }
        }
        if moved, let dock { AppController.shared.dockDropped(dock) }
    }

    override func rightMouseDown(with e: NSEvent) {
        HoverLabel.shared.hide()
        NSMenu.popUpContextMenu(AppController.shared.dockMenu(screenID: dock?.screenID), with: e, for: self)
    }

    // Dropping files: onto Trash (move to Trash), a folder (move/copy in), an app (open with), or empty space (pin)

    private func draggedURLs(_ sender: NSDraggingInfo) -> [URL] {
        (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    private func dropTarget(_ sender: NSDraggingInfo) -> IconView? {
        let p = convert(sender.draggingLocation, from: nil)
        return allViews.first { $0.frame.contains(p) }
    }

    private func copies(_ sender: NSDraggingInfo, into folder: URL) -> Bool {
        let mask = sender.draggingSourceOperationMask
        if !mask.contains(.move) && !mask.contains(.generic) { return true }
        if NSEvent.modifierFlags.contains(.option) { return true }
        return !draggedURLs(sender).allSatisfy { sameVolume($0, folder) }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let t = dropTarget(sender)
        let target = (t?.kind == .trash || t?.isFolder == true || t?.url.pathExtension == "app") ? t : nil
        for v in allViews where v !== target && v.magnification > 1 { v.setMagnification(1, genie: false) }
        target?.setMagnification(kMagnify, genie: true)
        if t?.kind == .trash { return .move }
        if let t, t.isFolder { return copies(sender, into: t.url) ? .copy : .move }
        return .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) {
        allViews.forEach { $0.setMagnification(1, genie: false) }
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        allViews.forEach { $0.setMagnification(1, genie: false) }
        let urls = draggedURLs(sender)
        guard !urls.isEmpty else { return false }
        let target = dropTarget(sender)
        if target?.kind == .trash {
            NSWorkspace.shared.recycle(urls) { _, _ in
                DispatchQueue.main.async { AppController.shared.updateTrash() }
            }
            return true
        }
        if let target, target.isFolder {
            dropFiles(urls, into: target.url, copy: copies(sender, into: target.url))
            return true
        }
        // Dropping documents onto an app icon opens them with that app.
        if let target, target.url.pathExtension == "app", !urls.allSatisfy({ $0.pathExtension == "app" }) {
            NSWorkspace.shared.open(urls, withApplicationAt: target.url, configuration: NSWorkspace.OpenConfiguration())
            return true
        }
        Store.shared.add(urls, at: insertionIndex(convert(sender.draggingLocation, from: nil)))
        return true
    }
}

// MARK: - Stacks (folder fan / grid)

final class FlippedView: NSView { override var isFlipped: Bool { true } }

final class StackItemView: NSView, NSDraggingSource {
    enum Style { case grid, fanLabelLeft, fanLabelRight }
    static let gridCell = NSSize(width: 92, height: 100)
    static let fanIcon: CGFloat = 36
    static let fanFont = NSFont.systemFont(ofSize: 13, weight: .medium)

    let url: URL?          // nil for action rows such as "Open in Finder"
    let title: String
    let style: Style
    var image: NSImage { didSet { needsDisplay = true } }
    var onClick: () -> Void = {}
    private var hovering = false { didSet { needsDisplay = true } }

    init(url: URL?, title: String, image: NSImage, style: Style) {
        self.url = url
        self.title = title
        self.image = image
        self.style = style
        super.init(frame: .zero)
        wantsLayer = true
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        toolTip = style == .grid ? title : nil
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseEntered(with e: NSEvent) { hovering = true }
    override func mouseExited(with e: NSEvent) { hovering = false }

    static func fanSize(_ title: String) -> NSSize {
        let w = min((title as NSString).size(withAttributes: [.font: fanFont]).width + 24, 280)
        return NSSize(width: w + 8 + fanIcon, height: 44)
    }

    var iconRect: NSRect {
        switch style {
        case .grid: return NSRect(x: (bounds.width - 60) / 2, y: 6, width: 60, height: 60)
        case .fanLabelLeft: return NSRect(x: bounds.width - Self.fanIcon, y: (bounds.height - Self.fanIcon) / 2, width: Self.fanIcon, height: Self.fanIcon)
        case .fanLabelRight: return NSRect(x: 0, y: (bounds.height - Self.fanIcon) / 2, width: Self.fanIcon, height: Self.fanIcon)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        switch style {
        case .grid:
            if hovering {
                NSColor.labelColor.withAlphaComponent(0.1).setFill()
                NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 1), xRadius: 8, yRadius: 8).fill()
            }
            image.draw(in: aspectFit(image.size, in: iconRect), from: .zero, operation: .sourceOver, fraction: 1,
                       respectFlipped: true, hints: nil)
            para.lineBreakMode = .byWordWrapping
            (title as NSString).draw(with: NSRect(x: 4, y: 70, width: bounds.width - 8, height: 28),
                                     options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                     attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor,
                                                  .paragraphStyle: para])
        case .fanLabelLeft, .fanLabelRight:
            let pillW = bounds.width - 8 - Self.fanIcon
            let pill = NSRect(x: style == .fanLabelLeft ? 0 : Self.fanIcon + 8, y: (bounds.height - 24) / 2, width: pillW, height: 24)
            (hovering ? NSColor.controlAccentColor : NSColor(white: 0.12, alpha: 0.85)).setFill()
            NSBezierPath(roundedRect: pill, xRadius: 12, yRadius: 12).fill()
            para.lineBreakMode = .byTruncatingTail
            let attrs: [NSAttributedString.Key: Any] = [.font: Self.fanFont, .foregroundColor: NSColor.white, .paragraphStyle: para]
            let h = (title as NSString).size(withAttributes: attrs).height
            (title as NSString).draw(with: NSRect(x: pill.minX + 12, y: pill.midY - h / 2, width: pill.width - 24, height: h),
                                     options: [.usesLineFragmentOrigin], attributes: attrs)
            image.draw(in: aspectFit(image.size, in: iconRect), from: .zero, operation: .sourceOver, fraction: 1,
                       respectFlipped: true, hints: nil)
        }
    }

    override func rightMouseDown(with e: NSEvent) {
        guard let url else { return }
        StackController.shared.showItemMenu(for: url, event: e, in: self)
    }

    override func mouseDown(with e: NSEvent) {
        if e.modifierFlags.contains(.control) { rightMouseDown(with: e); return }
        guard let window else { return }
        let start = e.locationInWindow
        while let ev = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if ev.type == .leftMouseUp { onClick(); return }
            let p = ev.locationInWindow
            if let url, hypot(p.x - start.x, p.y - start.y) > 4 {
                let item = NSDraggingItem(pasteboardWriter: url as NSURL)
                item.setDraggingFrame(aspectFit(image.size, in: iconRect), contents: image)
                beginDraggingSession(with: [item], event: ev, source: self)
                return
            }
        }
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        [.copy, .move, .link, .generic]
    }
    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        StackController.shared.externalDragBegan()
    }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        StackController.shared.externalDragEnded()
    }
}

final class StackPanel: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

final class StackController: NSObject, NSWindowDelegate {
    static let shared = StackController()
    private var panel: StackPanel?
    var isOpen: Bool { panel != nil }
    private var folder: URL?
    private var monitors: [Any] = []
    private var lastDismiss: (url: URL?, event: Int)?
    private var thumbRequests: [QLThumbnailGenerator.Request] = []
    private var dragging = false
    private var modal = false
    private weak var sourceIcon: IconView?

    func toggle(_ icon: IconView, event: NSEvent?) {
        if let event, let last = lastDismiss, last.event == event.eventNumber, last.url == icon.url { return }
        if panel != nil && folder == icon.url { dismiss(); return }
        dismiss()
        show(icon, animated: true)
    }

    private func entries(_ folder: URL, sort: StackSort) -> [URL] {
        let keys: [URLResourceKey] = [.addedToDirectoryDateKey, .contentModificationDateKey, .creationDateKey,
                                      .localizedNameKey, .localizedTypeDescriptionKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys,
                                                                     options: [.skipsHiddenFiles]) else { return [] }
        let vals = Dictionary(urls.map { ($0, try? $0.resourceValues(forKeys: Set(keys))) }, uniquingKeysWith: { a, _ in a })
        let name = { (u: URL) in vals[u]??.localizedName ?? u.lastPathComponent }
        let byName = { (a: URL, b: URL) in name(a).localizedStandardCompare(name(b)) == .orderedAscending }
        let date = { (u: URL, k: StackSort) -> Date in
            let v = vals[u] ?? nil
            switch k {
            case .dateAdded: return v?.addedToDirectoryDate ?? v?.creationDate ?? .distantPast
            case .dateModified: return v?.contentModificationDate ?? .distantPast
            default: return v?.creationDate ?? .distantPast
            }
        }
        switch sort {
        case .name: return urls.sorted(by: byName)
        case .kind:
            return urls.sorted {
                let ka = vals[$0]??.localizedTypeDescription ?? "", kb = vals[$1]??.localizedTypeDescription ?? ""
                return ka == kb ? byName($0, $1) : ka.localizedStandardCompare(kb) == .orderedAscending
            }
        default: return urls.sorted { date($0, sort) > date($1, sort) }
        }
    }

    private func show(_ icon: IconView, animated: Bool) {
        guard let anchor = icon.screenIconRect, let screen = icon.window?.screen else { return }
        HoverLabel.shared.hide()
        let list = entries(icon.url, sort: Store.shared.stackSort(for: icon.url))
        let p = StackPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .popUpMenu
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        p.delegate = self
        p.onEscape = { [weak self] in self?.dismiss() }
        folder = icon.url
        sourceIcon = icon
        panel = p
        if Store.shared.stackStyle(for: icon.url) == .fan {
            buildFan(p, icon: icon, list: list, anchor: anchor, screen: screen, animated: animated)
        } else {
            buildGrid(p, icon: icon, list: list, anchor: anchor, screen: screen, animated: animated)
        }
        p.makeKeyAndOrderFront(nil)

        if let g = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            if self?.modal == false { self?.dismiss() }
        }) { monitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] e in
            if let self, !self.modal, e.window !== self.panel {
                self.lastDismiss = (self.folder, e.eventNumber)
                self.dismiss()
            }
            return e
        }) { monitors.append(l) }
    }

    private func openFolder() {
        if let folder { NSWorkspace.shared.open(folder) }
        dismiss()
    }

    private func item(_ url: URL, style: StackItemView.Style, thumbSize: CGFloat) -> StackItemView {
        let v = StackItemView(url: url, title: displayName(url), image: NSWorkspace.shared.icon(forFile: url.path), style: style)
        v.onClick = { [weak self] in
            NSWorkspace.shared.open(url)
            self?.dismiss()
        }
        if !url.hasDirectoryPath && url.pathExtension != "app" {
            let req = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: thumbSize, height: thumbSize),
                                                   scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
            thumbRequests.append(req)
            QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { [weak v] rep, _ in
                guard let img = rep?.nsImage else { return }
                DispatchQueue.main.async { v?.image = img }
            }
        }
        return v
    }

    private func buildGrid(_ p: StackPanel, icon: IconView, list: [URL], anchor: NSRect, screen: NSScreen, animated: Bool) {
        let shown = Array(list.prefix(400))
        let cell = StackItemView.gridCell
        let n = shown.count
        let cols = max(3, min(7, Int(Double(max(n, 1)).squareRoot().rounded(.up))))
        let rows = max(1, Int((Double(n) / Double(cols)).rounded(.up)))
        let vf = screen.visibleFrame
        let header: CGFloat = 40, pad: CGFloat = 12
        let gridH = min(CGFloat(rows) * cell.height, min(4.5 * cell.height, vf.height - header - pad - 60))
        let W = CGFloat(cols) * cell.width + pad * 2
        let H = header + gridH + pad
        let gap = icon.s * (kMagnify - 1) + 12
        var o: NSPoint
        switch icon.dotSide {
        case .bottom: o = NSPoint(x: anchor.midX - W / 2, y: anchor.maxY + gap)
        case .top: o = NSPoint(x: anchor.midX - W / 2, y: anchor.minY - gap - H)
        case .left: o = NSPoint(x: anchor.maxX + gap, y: anchor.midY - H / 2)
        default: o = NSPoint(x: anchor.minX - gap - W, y: anchor.midY - H / 2)
        }
        o.x = max(vf.minX + 4, min(o.x, vf.maxX - W - 4))
        o.y = max(vf.minY + 4, min(o.y, vf.maxY - H - 4))
        p.setFrame(NSRect(origin: o, size: NSSize(width: W, height: H)), display: false)
        p.hasShadow = true

        let root = NSView(frame: NSRect(x: 0, y: 0, width: W, height: H))
        root.wantsLayer = true
        let fx = NSVisualEffectView(frame: root.bounds)
        fx.material = .popover
        fx.state = .active
        fx.blendingMode = .behindWindow
        fx.maskImage = roundedMask(14)
        fx.autoresizingMask = [.width, .height]
        root.addSubview(fx)

        let title = NSTextField(labelWithString: displayName(icon.url))
        title.font = .boldSystemFont(ofSize: 14)
        title.lineBreakMode = .byTruncatingTail
        let btn = NSButton(title: "Open in Finder", target: self, action: #selector(openFinderClicked))
        btn.bezelStyle = .rounded
        btn.controlSize = .small
        btn.sizeToFit()
        btn.frame.origin = NSPoint(x: W - pad - btn.frame.width, y: H - header + (header - btn.frame.height) / 2)
        title.frame = NSRect(x: pad + 4, y: H - header + (header - 18) / 2, width: btn.frame.minX - pad - 12, height: 18)
        root.addSubview(title)
        root.addSubview(btn)

        let scroll = NSScrollView(frame: NSRect(x: pad, y: pad, width: W - pad * 2, height: gridH))
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = CGFloat(rows) * cell.height > gridH
        scroll.autohidesScrollers = true
        let doc = FlippedView(frame: NSRect(x: 0, y: 0, width: W - pad * 2, height: max(CGFloat(rows) * cell.height, gridH)))
        for (i, u) in shown.enumerated() {
            let v = item(u, style: .grid, thumbSize: 60)
            v.frame = NSRect(x: CGFloat(i % cols) * cell.width, y: CGFloat(i / cols) * cell.height, width: cell.width, height: cell.height)
            doc.addSubview(v)
        }
        if n == 0 {
            let empty = NSTextField(labelWithString: "Folder is empty")
            empty.textColor = .secondaryLabelColor
            empty.sizeToFit()
            empty.frame.origin = NSPoint(x: (doc.bounds.width - empty.frame.width) / 2, y: 30)
            doc.addSubview(empty)
        }
        scroll.documentView = doc
        root.addSubview(scroll)
        p.contentView = root

        // Genie in: squeeze out of the dock icon, stretching away from the edge first.
        guard animated, let layer = root.layer else { return }
        let src = NSPoint(x: max(0, min(W, anchor.midX - o.x)), y: max(0, min(H, anchor.midY - o.y)))
        let alongY = icon.dotSide == .bottom || icon.dotSide == .top
        let t = { (lat: CGFloat, away: CGFloat) in
            scaleAbout(layer, src, sx: alongY ? lat : away, sy: alongY ? away : lat)
        }
        let k = CAKeyframeAnimation(keyPath: "transform")
        k.values = [t(0.06, 0.12), t(0.4, 1.04), t(1.03, 0.99), t(1, 1)].map { NSValue(caTransform3D: $0) }
        k.keyTimes = [0, 0.45, 0.8, 1]
        k.timingFunctions = [CAMediaTimingFunction(name: .easeIn), CAMediaTimingFunction(name: .easeOut),
                             CAMediaTimingFunction(name: .easeInEaseOut)]
        k.duration = 0.32
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.14
        layer.add(k, forKey: "genie")
        layer.add(fade, forKey: "fade")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak p] in p?.invalidateShadow() }
    }

    private func buildFan(_ p: StackPanel, icon: IconView, list: [URL], anchor: NSRect, screen: NSScreen, animated: Bool) {
        let vf = screen.visibleFrame
        let grow = icon.s * (kMagnify - 1)
        let step: CGFloat = 46
        let half = StackItemView.fanIcon / 2
        let up: Bool, curve: CGFloat, labelLeft: Bool
        var origin: NSPoint   // center of the first row's icon
        switch icon.dotSide {
        case .bottom: up = true; curve = 1; labelLeft = true; origin = NSPoint(x: anchor.midX, y: anchor.maxY + grow + 34)
        case .top: up = false; curve = 1; labelLeft = true; origin = NSPoint(x: anchor.midX, y: anchor.minY - grow - 34)
        case .left: up = anchor.midY < vf.midY; curve = 1; labelLeft = false; origin = NSPoint(x: anchor.maxX + grow + 34, y: anchor.midY)
        default: up = anchor.midY < vf.midY; curve = -1; labelLeft = true; origin = NSPoint(x: anchor.minX - grow - 34, y: anchor.midY)
        }
        let dir: CGFloat = up ? 1 : -1
        let room = up ? vf.maxY - origin.y : origin.y - vf.minY
        let maxRows = max(1, Int(room / step))
        let shown = Array(list.prefix(max(0, min(15, maxRows - 1))))
        let more = list.count - shown.count
        let style: StackItemView.Style = labelLeft ? .fanLabelLeft : .fanLabelRight

        var views: [StackItemView] = shown.map { item($0, style: style, thumbSize: 36) }
        let finder = StackItemView(url: nil, title: more > 0 ? "Open in Finder (\(more) more)" : "Open in Finder",
                                   image: NSWorkspace.shared.icon(forFile: icon.url.path), style: style)
        finder.onClick = { [weak self] in self?.openFolder() }
        views.append(finder)

        let n = views.count
        var frames: [NSRect] = []
        var angles: [CGFloat] = []
        for (i, v) in views.enumerated() {
            let t = n > 1 ? CGFloat(i) / CGFloat(n - 1) : 0
            let cx = origin.x + curve * 80 * t * t
            let cy = origin.y + dir * CGFloat(i) * step
            let size = StackItemView.fanSize(v.title)
            let x = labelLeft ? cx + half - size.width : cx - half
            frames.append(NSRect(x: x, y: cy - size.height / 2, width: size.width, height: size.height))
            angles.append(-curve * dir * 7 * t * t)
        }
        var box = frames.dropFirst().reduce(frames[0]) { $0.union($1) }.insetBy(dx: -30, dy: -30)
        let shift = max(0, vf.minX - box.minX) - max(0, box.maxX - vf.maxX)
        box.origin.x += shift
        p.setFrame(box, display: false)
        p.hasShadow = false

        let root = NSView(frame: NSRect(origin: .zero, size: box.size))
        root.wantsLayer = true
        let iconPt = NSPoint(x: anchor.midX - box.minX, y: anchor.midY - box.minY)
        let now = CACurrentMediaTime()
        for (i, v) in views.enumerated() {
            let f = frames[i].offsetBy(dx: shift - box.minX, dy: -box.minY)
            let host = NSView(frame: f)
            host.wantsLayer = true
            host.clipsToBounds = false
            v.frame = host.bounds
            host.addSubview(v)
            v.frameCenterRotation = angles[i]
            v.layer?.shadowOpacity = 0.25
            v.layer?.shadowRadius = 4
            v.layer?.shadowOffset = CGSize(width: 0, height: -1)
            root.addSubview(host)
            guard animated, let layer = host.layer else { continue }
            let c = NSPoint(x: layer.bounds.midX, y: layer.bounds.midY)
            let from = scaleAbout(layer, c, sx: 0.25, sy: 0.25, dx: iconPt.x - f.midX, dy: iconPt.y - f.midY)
            let a = CASpringAnimation(keyPath: "transform")
            a.fromValue = NSValue(caTransform3D: from)
            a.toValue = NSValue(caTransform3D: CATransform3DIdentity)
            a.mass = 0.7
            a.stiffness = 240
            a.damping = 19
            a.duration = a.settlingDuration
            a.beginTime = now + Double(i) * 0.018
            a.fillMode = .backwards
            let o = CABasicAnimation(keyPath: "opacity")
            o.fromValue = 0
            o.toValue = 1
            o.duration = 0.12
            o.beginTime = a.beginTime
            o.fillMode = .backwards
            layer.add(a, forKey: "fan")
            layer.add(o, forKey: "fade")
        }
        p.contentView = root
    }

    @objc private func openFinderClicked() { openFolder() }

    /// Re-reads the folder after a change, without replaying the open animation.
    private func reload() {
        guard let icon = sourceIcon else { dismiss(); return }
        if let p = panel { p.orderOut(nil) }
        let wasOpen = panel != nil
        panel = nil
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        if wasOpen { show(icon, animated: false) }
    }

    func showItemMenu(for url: URL, event: NSEvent, in view: NSView) {
        let m = NSMenu()
        m.addItem(NSMenuItem(title: displayName(url), action: nil, keyEquivalent: ""))
        m.addItem(.separator())
        m.addItem(ActionItem("Open") { [weak self] in
            NSWorkspace.shared.open(url)
            self?.dismiss()
        })
        m.addItem(ActionItem("Open Folder") { [weak self] in
            NSWorkspace.shared.activateFileViewerSelecting([url])
            self?.dismiss()
        })
        m.addItem(.separator())
        m.addItem(ActionItem("Copy") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([url as NSURL])
        })
        m.addItem(ActionItem("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.path, forType: .string)
        })
        m.addItem(ActionItem("Rename…") { [weak self] in self?.rename(url) })
        m.addItem(.separator())
        m.addItem(ActionItem("Move to Trash") { [weak self] in
            NSWorkspace.shared.recycle([url]) { _, _ in
                DispatchQueue.main.async {
                    AppController.shared.updateTrash()
                    self?.reload()
                }
            }
        })
        NSMenu.popUpContextMenu(m, with: event, for: view)
    }

    private func rename(_ url: URL) {
        modal = true
        defer { modal = false }
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Rename “\(url.lastPathComponent)”"
        a.addButton(withTitle: "Rename")
        a.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = url.lastPathComponent
        a.accessoryView = field
        a.window.initialFirstResponder = field
        DispatchQueue.main.async {
            let stem = (url.lastPathComponent as NSString).deletingPathExtension
            field.currentEditor()?.selectedRange = NSRange(location: 0, length: (stem as NSString).length)
        }
        guard a.runModal() == .alertFirstButtonReturn else { panel?.makeKey(); return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != url.lastPathComponent, !name.contains("/") else { panel?.makeKey(); return }
        do {
            try FileManager.default.moveItem(at: url, to: url.deletingLastPathComponent().appendingPathComponent(name))
        } catch {
            let e = NSAlert(error: error)
            e.runModal()
        }
        reload()
    }

    func externalDragBegan() {
        dragging = true
        panel?.alphaValue = 0
        panel?.ignoresMouseEvents = true
    }
    func externalDragEnded() {
        dragging = false
        dismiss()
    }

    func windowDidResignKey(_ notification: Notification) {
        if !dragging && !modal { dismiss() }
    }

    func dismiss() {
        guard let p = panel else { return }
        panel = nil
        folder = nil
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        thumbRequests.forEach { QLThumbnailGenerator.shared.cancel($0) }
        thumbRequests = []
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.12; p.animator().alphaValue = 0 },
                                             completionHandler: { p.orderOut(nil) })
    }
}

// MARK: - Dock mode (keeps other windows out from behind edge-pinned docks)

final class DockMode {
    static let shared = DockMode()
    private var timer: Timer?

    func update() {
        guard Store.shared.dockMode else {
            timer?.invalidate()
            timer = nil
            return
        }
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick(allApps: false) }
        }
        tick(allApps: true)
    }

    /// Strips of screen (Cocoa coordinates) that edge-pinned docks reserve.
    private func reserved() -> [(Edge, NSRect)] {
        AppController.shared.docks.values.compactMap { d in
            guard !d.autoHide else { return nil }
            let f = d.panel.frame, s = d.screen.frame, g: CGFloat = 4
            switch Store.shared.placement(for: d.screenID).edge {
            case .left: return (.left, NSRect(x: s.minX, y: s.minY, width: f.maxX + g - s.minX, height: s.height))
            case .right: return (.right, NSRect(x: f.minX - g, y: s.minY, width: s.maxX - f.minX + g, height: s.height))
            case .bottom: return (.bottom, NSRect(x: s.minX, y: s.minY, width: s.width, height: f.maxY + g - s.minY))
            case .top: return (.top, NSRect(x: s.minX, y: f.minY - g, width: s.width, height: s.maxY - f.minY + g))
            case .free: return nil
            }
        }
    }

    private func tick(allApps: Bool) {
        guard AXIsProcessTrusted(), NSEvent.pressedMouseButtons == 0 else { return }
        let strips = reserved()
        guard !strips.isEmpty else { return }
        let apps = allApps ? NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
                           : [NSWorkspace.shared.frontmostApplication].compactMap { $0 }
        for app in apps where app.processIdentifier != getpid() {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            var val: CFTypeRef?
            guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &val) == .success,
                  let wins = val as? [AXUIElement] else { continue }
            for w in wins { adjust(w, strips) }
        }
    }

    private func value<T>(_ w: AXUIElement, _ attr: String, _ type: AXValueType, _ empty: T) -> T? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(w, attr as CFString, &v) == .success, let v,
              CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var out = empty
        return AXValueGetValue(v as! AXValue, type, &out) ? out : nil
    }

    private func adjust(_ w: AXUIElement, _ strips: [(Edge, NSRect)]) {
        var v: CFTypeRef?
        AXUIElementCopyAttributeValue(w, kAXSubroleAttribute as CFString, &v)
        guard (v as? String) == (kAXStandardWindowSubrole as String) else { return }
        v = nil
        AXUIElementCopyAttributeValue(w, "AXFullScreen" as CFString, &v)
        if (v as? Bool) == true { return }
        v = nil
        AXUIElementCopyAttributeValue(w, kAXMinimizedAttribute as CFString, &v)
        if (v as? Bool) == true { return }
        guard let pos = value(w, kAXPositionAttribute, .cgPoint, CGPoint.zero),
              let size = value(w, kAXSizeAttribute, .cgSize, CGSize.zero),
              let primary = NSScreen.screens.first?.frame else { return }

        let original = NSRect(x: pos.x, y: primary.height - pos.y - size.height, width: size.width, height: size.height)
        var f = original
        for (edge, r) in strips where r.intersects(f) {
            switch edge {
            case .left:
                if f.maxX - r.maxX >= 300 { f.size.width = f.maxX - r.maxX }
                f.origin.x = r.maxX
            case .right:
                if r.minX - f.minX >= 300 { f.size.width = r.minX - f.minX } else { f.origin.x = r.minX - f.width }
            case .bottom:
                if f.maxY - r.maxY >= 200 { f.size.height = f.maxY - r.maxY }
                f.origin.y = r.maxY
            case .top:
                if r.minY - f.minY >= 200 { f.size.height = r.minY - f.minY } else { f.origin.y = r.minY - f.height }
            case .free: break
            }
        }
        guard f != original else { return }
        var newPos = CGPoint(x: f.minX, y: primary.height - f.maxY)
        var newSize = CGSize(width: f.width, height: f.height)
        if let p = AXValueCreate(.cgPoint, &newPos), let s = AXValueCreate(.cgSize, &newSize) {
            AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, p)
            AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, s)
            AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, p)
        }
    }
}

// MARK: - Dock window (one per screen)

final class DockPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

func roundedMask(_ r: CGFloat) -> NSImage {
    let e = 2 * r + 1
    let img = NSImage(size: NSSize(width: e, height: e), flipped: false) { rect in
        NSColor.black.set()
        NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).fill()
        return true
    }
    img.capInsets = NSEdgeInsets(top: r, left: r, bottom: r, right: r)
    img.resizingMode = .stretch
    return img
}

func frameFor(size: NSSize, placement p: Placement, in vf: NSRect) -> NSRect {
    var x = vf.minX + p.fx * vf.width - size.width / 2
    var y = vf.minY + p.fy * vf.height - size.height / 2
    switch p.edge {
    case .left: x = vf.minX + kMargin
    case .right: x = vf.maxX - size.width - kMargin
    case .bottom: y = vf.minY + kMargin
    case .top: y = vf.maxY - size.height - kMargin
    case .free: break
    }
    x = max(vf.minX, min(x, vf.maxX - size.width))
    y = max(vf.minY, min(y, vf.maxY - size.height))
    return NSRect(origin: NSPoint(x: x, y: y), size: size)
}

final class Dock {
    let screenID: String
    var screen: NSScreen
    let panel: DockPanel
    let view = DockView()

    init(screen: NSScreen) {
        self.screen = screen
        screenID = screen.stableID
        panel = DockPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        let fx = NSVisualEffectView()
        fx.material = .popover
        fx.blendingMode = .behindWindow
        fx.state = .active
        fx.maskImage = roundedMask(14)
        panel.contentView = fx
        fx.addSubview(view)
        view.dock = self
    }

    func refresh(animated: Bool) {
        let store = Store.shared
        let p = store.placement(for: screenID)
        panel.level = store.alwaysOnTop || store.dockMode ? .floating : .normal
        let vf = screen.visibleFrame
        view.configure(items: store.items, running: store.showRunning ? AppController.shared.runningExtras() : [],
                       size: store.iconSize, spacing: store.spacing, locked: store.locked,
                       showTrash: store.showTrash, trashFull: AppController.shared.trashFull,
                       vertical: p.isVertical, edge: p.edge,
                       maxLength: (p.isVertical ? vf.height : vf.width) - 2 * kMargin,
                       runningPaths: AppController.shared.running)
        let size = view.preferredSize
        view.frame = NSRect(origin: .zero, size: size)
        let f = frameFor(size: size, placement: p, in: vf)
        shownFrame = f
        if autoHide && hidden {
            panel.setFrame(hiddenFrame, display: false)
            return
        }
        hidden = false
        panel.alphaValue = 1
        if animated && panel.isVisible {
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.2; panel.animator().setFrame(f, display: true) },
                                                 completionHandler: { [panel] in panel.invalidateShadow() })
        } else {
            panel.setFrame(f, display: true)
            panel.invalidateShadow()
        }
        panel.orderFrontRegardless()
    }

    // MARK: Auto-hide

    private(set) var hidden = false
    private var shownFrame = NSRect.zero
    private var edgeSince: Date?
    private var awaySince: Date?

    /// Auto-hide applies only to docks pinned to an edge.
    var autoHide: Bool {
        Store.shared.autoHide(for: screenID) && Store.shared.placement(for: screenID).edge != .free
    }

    private var edge: Edge { Store.shared.placement(for: screenID).edge }

    /// Just past the screen edge the dock is pinned to.
    private var hiddenFrame: NSRect {
        let f = shownFrame
        switch edge {
        case .left: return f.offsetBy(dx: -(f.width + kMargin), dy: 0)
        case .right: return f.offsetBy(dx: f.width + kMargin, dy: 0)
        case .top: return f.offsetBy(dx: 0, dy: f.height + kMargin)
        default: return f.offsetBy(dx: 0, dy: -(f.height + kMargin))
        }
    }

    /// Pointer is pressed against the dock's screen edge.
    private func atEdge(_ m: NSPoint) -> Bool {
        let s = screen.frame, t: CGFloat = 3
        guard m.x >= s.minX - 1, m.x <= s.maxX + 1, m.y >= s.minY - 1, m.y <= s.maxY + 1 else { return false }
        switch edge {
        case .left: return m.x - s.minX <= t
        case .right: return s.maxX - m.x <= t
        case .top: return s.maxY - m.y <= t
        case .bottom: return m.y - s.minY <= t
        case .free: return false
        }
    }

    func tickAutoHide(_ m: NSPoint) {
        guard autoHide else {
            if hidden { refresh(animated: false) }
            return
        }
        let now = Date()
        if hidden {
            if atEdge(m) {
                edgeSince = edgeSince ?? now
                if now.timeIntervalSince(edgeSince!) >= 0.2 { reveal() }
            } else {
                edgeSince = nil
            }
            return
        }
        let busy = StackController.shared.isOpen || AppController.shared.menuDepth > 0 || NSEvent.pressedMouseButtons != 0
        let near = shownFrame.insetBy(dx: -24, dy: -24).contains(m) || atEdge(m)
        if busy || near {
            awaySince = nil
        } else {
            awaySince = awaySince ?? now
            if now.timeIntervalSince(awaySince!) >= 0.5 { conceal() }
        }
    }

    private func conceal() {
        hidden = true
        awaySince = nil
        HoverLabel.shared.hide()
        let target = hiddenFrame
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.hidden else { return }
            self.panel.orderOut(nil)
        })
    }

    func reveal() {
        guard hidden else { return }
        hidden = false
        edgeSince = nil
        awaySince = nil
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.setFrame(hiddenFrame, display: false)
            panel.orderFrontRegardless()
        }
        let target = shownFrame
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 1
        }, completionHandler: { [panel] in panel.invalidateShadow() })
    }
}

// MARK: - Global hotkey (⌃⌥D toggles Auto-Hide on the screen under the pointer)

func registerAutoHideHotKey() {
    var ref: EventHotKeyRef?
    let id = EventHotKeyID(signature: OSType(0x5144_4B31), id: 1)  // 'QDK1'
    RegisterEventHotKey(UInt32(kVK_ANSI_D), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &ref)
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
        AppController.shared.toggleAutoHideUnderPointer()
        return noErr
    }, 1, &spec, nil, nil)
}

// MARK: - macOS Dock (hide / restore)

/// Hides the built-in Dock by auto-hiding it with a very long reveal delay, so it never appears.
/// It can't be quit: its process also runs ⌘-Tab, Mission Control and Spaces.
enum SystemDock {
    private static let domain = "com.apple.dock"
    private static let savedKey = "systemDockSaved"

    private static func run(_ path: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        try? p.run()
        p.waitUntilExit()
    }
    private static func read(_ key: String) -> Any? { CFPreferencesCopyAppValue(key as CFString, domain as CFString) }

    static var isHidden: Bool {
        (read("autohide") as? Bool ?? false) && ((read("autohide-delay") as? NSNumber)?.doubleValue ?? 0) >= 999
    }

    static func hide() {
        let d = UserDefaults.standard
        if d.dictionary(forKey: savedKey) == nil && !isHidden {
            var saved: [String: Any] = ["autohide": read("autohide") as? Bool ?? false]
            if let delay = read("autohide-delay") as? NSNumber { saved["delay"] = delay.doubleValue }
            d.set(saved, forKey: savedKey)
        }
        guard !isHidden else { return }
        run("/usr/bin/defaults", ["write", domain, "autohide", "-bool", "true"])
        run("/usr/bin/defaults", ["write", domain, "autohide-delay", "-float", "1000"])
        run("/usr/bin/killall", ["Dock"])
    }

    /// Puts back the auto-hide settings saved before Q-Dock hid the Dock.
    static func restore() {
        let d = UserDefaults.standard
        let saved = d.dictionary(forKey: savedKey) ?? ["autohide": false]
        run("/usr/bin/defaults", ["write", domain, "autohide", "-bool", (saved["autohide"] as? Bool ?? false) ? "true" : "false"])
        if let delay = saved["delay"] as? Double {
            run("/usr/bin/defaults", ["write", domain, "autohide-delay", "-float", String(delay)])
        } else {
            run("/usr/bin/defaults", ["delete", domain, "autohide-delay"])
        }
        d.removeObject(forKey: savedKey)
        run("/usr/bin/killall", ["Dock"])
    }
}

// MARK: - Setup assistant

func hasFullDiskAccess() -> Bool {
    FileHandle(forReadingAtPath: "/Library/Application Support/com.apple.TCC/TCC.db") != nil
}

func openPrivacyPane(_ anchor: String) {
    if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") { NSWorkspace.shared.open(u) }
}

/// Replaces the dock's items with the ones pinned in the macOS Dock (Finder first).
func importSystemDock() { Store.shared.items = systemDockItems() }

/// Apps and folders pinned in the macOS Dock, with Finder first.
func systemDockItems() -> [URL] {
    var urls = [URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")]
    guard let d = UserDefaults(suiteName: "com.apple.dock") else { return urls }
    for key in ["persistent-apps", "persistent-others"] {
        for tile in d.array(forKey: key) as? [[String: Any]] ?? [] {
            let file = (tile["tile-data"] as? [String: Any])?["file-data"] as? [String: Any]
            if let s = file?["_CFURLString"] as? String, let u = URL(string: s), u.isFileURL {
                urls.append(URL(fileURLWithPath: u.path))
            }
        }
    }
    return urls
}

final class Onboarding {
    static let shared = Onboarding()
    private var window: NSWindow?

    func showIfNeeded() {
        if !UserDefaults.standard.bool(forKey: "onboarded") { show() }
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        if let window { window.makeKeyAndOrderFront(nil); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 500),
                         styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: OnboardingView { [weak self] in self?.window?.close() })
        w.center()
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in
            UserDefaults.standard.set(true, forKey: "onboarded")
            self?.window = nil
        }
        window = w
        w.makeKeyAndOrderFront(nil)
    }
}

struct OnboardingView: View {
    let finish: () -> Void
    @State private var step = 0
    @State private var axGranted = AXIsProcessTrusted()
    @State private var fdaGranted = hasFullDiskAccess()
    @State private var loginItem = SMAppService.mainApp.status == .enabled
    @State private var imported = false
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var hideDock = Store.shared.hideSystemDock
    @State private var restoreOnQuit = Store.shared.restoreSystemDockOnQuit
    private let steps = 4

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: welcome
                case 1: permissions
                case 2: systemDock
                default: tips
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 36)
            .padding(.top, 40)
            Divider()
            HStack {
                HStack(spacing: 6) {
                    ForEach(0..<steps, id: \.self) { i in
                        Circle().fill(i == step ? Color.accentColor : Color.secondary.opacity(0.3)).frame(width: 7, height: 7)
                    }
                }
                Spacer()
                if step > 0 { Button("Back") { step -= 1 } }
                Button(step == steps - 1 ? "Get Started" : "Continue") {
                    if step == steps - 1 { finish() } else { step += 1 }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 580, height: 500)
        .onReceive(tick) { _ in
            axGranted = AXIsProcessTrusted()
            fdaGranted = hasFullDiskAccess()
            loginItem = SMAppService.mainApp.status == .enabled
        }
    }

    private var welcome: some View {
        VStack(spacing: 18) {
            Image(systemName: "dock.rectangle")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(Color.accentColor)
            Text("Welcome to Q-Dock").font(.largeTitle.bold())
            Text("A dock you can pin to any edge of any screen — or float anywhere. Every display gets its own copy, positioned independently.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
            Spacer().frame(height: 8)
            Button {
                importSystemDock()
                imported = true
            } label: {
                Label(imported ? "Imported your macOS Dock items" : "Import my macOS Dock items",
                      systemImage: imported ? "checkmark.circle.fill" : "square.and.arrow.down")
            }
            .controlSize(.large)
            .disabled(imported)
            Text("Optional — replaces Q-Dock's items with the apps and folders in your macOS Dock.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Permissions").font(.title.bold())
            Text("Q-Dock works without these, but a few features need them.").foregroundStyle(.secondary)
            PermissionRow(icon: "macwindow.on.rectangle", title: "Accessibility",
                          detail: "Needed for Dock Mode, which moves other windows out from behind the dock.",
                          granted: axGranted, buttonTitle: "Grant Access") {
                _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
                openPrivacyPane("Privacy_Accessibility")
            }
            PermissionRow(icon: "externaldrive", title: "Full Disk Access",
                          detail: "Lets the Trash icon show when it's full, and lets folder stacks open protected folders. In Settings, click +, then choose Q-Dock from Applications.",
                          granted: fdaGranted, buttonTitle: "Open Settings") {
                openPrivacyPane("Privacy_AllFiles")
            }
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "power").font(.title2).frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Launch at Login").font(.headline)
                    Text("Start Q-Dock automatically when you log in.").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(get: { loginItem }, set: { _ in
                    AppController.shared.toggleLoginItem()
                    loginItem = SMAppService.mainApp.status == .enabled
                }))
                .toggleStyle(.switch)
                .labelsHidden()
            }
        }
    }

    private var systemDock: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("The macOS Dock").font(.title.bold())
            Text("Q-Dock can hide the built-in Dock so it stops jumping between screens and popping up over your work. ⌘-Tab, Mission Control and Spaces keep working. You can change this anytime from the menu.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 14) {
                ChoiceCard(icon: "eye.slash", title: "Hide the macOS Dock", detail: "Use Q-Dock instead", selected: hideDock) {
                    hideDock = true
                    AppController.shared.setHideSystemDock(true)
                }
                ChoiceCard(icon: "eye", title: "Keep the macOS Dock", detail: "Use both docks", selected: !hideDock) {
                    hideDock = false
                    AppController.shared.setHideSystemDock(false)
                }
            }
            Toggle("Bring the macOS Dock back when Q-Dock quits", isOn: Binding(get: { restoreOnQuit }, set: {
                restoreOnQuit = $0
                Store.shared.restoreSystemDockOnQuit = $0
            }))
            .disabled(!hideDock)
        }
        .onAppear { Store.shared.askedSystemDock = true }
    }

    private var tips: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("The basics").font(.title.bold())
            TipRow(icon: "hand.draw", title: "Move it",
                   text: "Drag the ⋮⋮ grip (or any empty spot). Drop near an edge to pin, anywhere else to float. Lock Position hides the grip.")
            TipRow(icon: "cursorarrow.click.2", title: "Right-click for everything",
                   text: "Icon size, spacing, position, Auto-Hide (⌃⌥D), Dock Mode, running apps, Trash — or use the Q-Dock icon in the menu bar.")
            TipRow(icon: "square.and.arrow.down.on.square", title: "Drag and drop",
                   text: "Drop apps or files onto the dock to add them, onto a folder to move them in, or onto the Trash to delete. Drag an icon off the dock to remove it.")
            TipRow(icon: "folder", title: "Folders",
                   text: "Click a folder to open it as a Fan or Grid (right-click to switch). Drag files out, or right-click one to copy, rename or trash it.")
            TipRow(icon: "questionmark.circle", title: "Come back anytime",
                   text: "Open this again from the menu: Setup Assistant…")
        }
    }
}

struct PermissionRow: View {
    let icon: String, title: String, detail: String
    let granted: Bool
    let buttonTitle: String
    let action: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.title2).frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green).labelStyle(.titleAndIcon)
            } else {
                Button(buttonTitle, action: action)
            }
        }
    }
}

struct ChoiceCard: View {
    let icon: String, title: String, detail: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 28))
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(RoundedRectangle(cornerRadius: 12).fill(selected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: selected ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct TipRow: View {
    let icon: String, title: String, text: String
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.title3).foregroundStyle(Color.accentColor).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - App

final class AppController: NSObject, NSApplicationDelegate {
    static let shared = AppController()
    let store = Store.shared
    var docks: [String: Dock] = [:]
    var statusItem: NSStatusItem!
    var running: Set<String> = []
    var trashFull = false
    var menuDepth = 0
    private var autoHideTimer: Timer?

    func applicationDidFinishLaunching(_ n: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let b = statusItem.button {
            if let img = NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: "Q-Dock") {
                b.image = img
            } else {
                b.title = "⌂"
            }
            b.target = self
            b.action = #selector(statusClicked)
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        let nc = NotificationCenter.default
        nc.addObserver(forName: Store.changed, object: nil, queue: .main) { [weak self] _ in self?.rebuild(animated: true) }
        nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.rebuild(animated: false)
        }
        let wc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            wc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                self.updateRunning()
                if self.store.showRunning { self.rebuild(animated: true) }
            }
        }
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.updateTrash() }
        nc.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            self?.menuDepth += 1
        }
        nc.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.menuDepth = max(0, self.menuDepth - 1)
        }
        registerAutoHideHotKey()
        trashFull = trashIsFull()
        updateRunning()
        rebuild(animated: false)
        if store.hideSystemDock { SystemDock.hide() }
        Onboarding.shared.showIfNeeded()
        if UserDefaults.standard.bool(forKey: "onboarded") && !store.askedSystemDock {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.askAboutSystemDock() }
        }
        // `pkill`/logout send SIGTERM; route it through a normal quit so the macOS Dock gets restored.
        signal(SIGTERM, SIG_IGN)
        sigterm.setEventHandler { NSApp.terminate(nil) }
        sigterm.resume()
    }

    private let sigterm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)

    func applicationWillTerminate(_ notification: Notification) {
        if store.hideSystemDock && store.restoreSystemDockOnQuit { SystemDock.restore() }
    }

    func setHideSystemDock(_ hide: Bool) {
        store.askedSystemDock = true
        guard hide != store.hideSystemDock || hide != SystemDock.isHidden else { return }
        store.hideSystemDock = hide
        if hide { SystemDock.hide() } else { SystemDock.restore() }
    }

    /// One-time question for people who finished setup before this option existed.
    func askAboutSystemDock() {
        store.askedSystemDock = true
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Hide the macOS Dock?"
        a.informativeText = "Q-Dock can hide the built-in Dock so it stops jumping between screens and popping up over your work. "
            + "⌘-Tab, Mission Control and Spaces keep working. You can change this anytime from the Q-Dock menu."
        a.addButton(withTitle: "Hide macOS Dock")
        a.addButton(withTitle: "Keep macOS Dock")
        let box = NSButton(checkboxWithTitle: "Bring the macOS Dock back when Q-Dock quits", target: nil, action: nil)
        box.state = store.restoreSystemDockOnQuit ? .on : .off
        a.accessoryView = box
        let hide = a.runModal() == .alertFirstButtonReturn
        store.restoreSystemDockOnQuit = box.state == .on
        setHideSystemDock(hide)
    }

    func updateRunning() {
        running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleURL.map(canonicalPath) })
        docks.values.forEach { $0.view.refreshRunning(running) }
    }

    /// Regular apps that are running but not pinned, in launch order.
    func runningExtras() -> [URL] {
        var seen = Set(store.items.map(canonicalPath))
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != getpid() }
            .compactMap(\.bundleURL)
            .filter { seen.insert(canonicalPath($0)).inserted }
    }

    func updateTrash() {
        let full = trashIsFull()
        guard full != trashFull else { return }
        trashFull = full
        docks.values.forEach { $0.view.trash?.setImage(trashImage(full: full)) }
    }

    func rebuild(animated: Bool) {
        let screens = store.allScreens ? NSScreen.screens : Array(NSScreen.screens.prefix(1))
        let ids = Set(screens.map(\.stableID))
        for (id, d) in docks where !ids.contains(id) {
            d.panel.orderOut(nil)
            docks[id] = nil
        }
        for s in screens {
            let d = docks[s.stableID] ?? Dock(screen: s)
            docks[s.stableID] = d
            d.screen = s
            d.refresh(animated: animated)
        }
        DockMode.shared.update()
        updateAutoHideTimer()
    }

    /// Polls the pointer (20×/s) only while some dock is set to auto-hide.
    private func updateAutoHideTimer() {
        let needed = docks.values.contains { $0.autoHide || $0.hidden }
        if needed && autoHideTimer == nil {
            let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
                guard let self else { return }
                let m = NSEvent.mouseLocation
                self.docks.values.forEach { $0.tickAutoHide(m) }
            }
            RunLoop.main.add(t, forMode: .common)
            autoHideTimer = t
        } else if !needed {
            autoHideTimer?.invalidate()
            autoHideTimer = nil
        }
    }

    func toggleAutoHideUnderPointer() {
        let m = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(m, $0.frame, false) }),
              store.placement(for: screen.stableID).edge != .free else { NSSound.beep(); return }
        store.setAutoHide(!store.autoHide(for: screen.stableID), for: [screen.stableID])
    }

    /// Called after the user drags a dock; snaps to the nearest edge or leaves it floating.
    func dockDropped(_ dock: Dock) {
        let f = dock.panel.frame
        let c = NSPoint(x: f.midX, y: f.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(c) } ?? dock.screen
        let vf = screen.visibleFrame
        let dists: [(Edge, CGFloat)] = [(.left, f.minX - vf.minX), (.right, vf.maxX - f.maxX),
                                        (.bottom, f.minY - vf.minY), (.top, vf.maxY - f.maxY)]
        let nearest = dists.min { $0.1 < $1.1 }!
        let p = Placement(edge: nearest.1 < kSnap ? nearest.0 : .free,
                          fx: max(0, min(1, (c.x - vf.minX) / vf.width)),
                          fy: max(0, min(1, (c.y - vf.minY) / vf.height)),
                          vertical: store.placement(for: dock.screenID).isVertical)
        store.setPlacement(p, for: [screen.stableID])
    }

    func setEdge(_ edge: Edge, screenID: String?) {
        let ids = screenID.map { [$0] } ?? NSScreen.screens.map(\.stableID)
        for id in ids {
            var p = store.placement(for: id)
            let wasVertical = p.isVertical
            p.edge = edge
            switch edge {
            case .left, .right: p.fy = 0.5
            case .top, .bottom: p.fx = 0.5
            case .free: p.vertical = wasVertical; p.fx = 0.5; p.fy = 0.5
            }
            store.setPlacement(p, for: [id])
            if store.syncPositions { break }
        }
    }

    func dockMenu(screenID: String?) -> NSMenu {
        let m = NSMenu()
        m.autoenablesItems = false
        m.addItem(ActionItem("Add Apps or Files…") { [weak self] in self?.addItems() })
        m.addItem(.separator())

        let locked = store.locked
        let current = store.placement(for: screenID ?? NSScreen.screens.first?.stableID ?? "*")
        let pos = NSMenu()
        pos.autoenablesItems = false
        for (e, name) in [(Edge.left, "Left Edge"), (.right, "Right Edge"), (.top, "Top Edge"), (.bottom, "Bottom Edge"), (.free, "Floating")] {
            pos.addItem(ActionItem(name, checked: current.edge == e, enabled: !locked) { [weak self] in self?.setEdge(e, screenID: screenID) })
        }
        if current.edge == .free {
            pos.addItem(.separator())
            pos.addItem(ActionItem("Vertical", checked: current.vertical, enabled: !locked) { [weak self] in
                guard let self else { return }
                var p = current
                p.vertical.toggle()
                self.store.setPlacement(p, for: screenID.map { [$0] } ?? NSScreen.screens.map(\.stableID))
            })
        }
        m.addItem(submenuItem(screenID == nil ? "Position (all screens)" : "Position (this screen)", pos))

        let sizes = NSMenu()
        for (v, name) in [(28, "Tiny"), (32, "Small"), (40, "Medium-Small"), (48, "Medium"), (56, "Medium-Large"), (64, "Large"), (80, "Huge")] {
            sizes.addItem(ActionItem(name, checked: Int(store.iconSize) == v) { [weak self] in self?.store.iconSize = CGFloat(v) })
        }
        m.addItem(submenuItem("Icon Size", sizes))

        let gaps = NSMenu()
        for (v, name) in [(0, "Tight"), (2, "Compact"), (6, "Normal"), (12, "Roomy")] {
            gaps.addItem(ActionItem(name, checked: Int(store.spacing) == v) { [weak self] in self?.store.spacing = CGFloat(v) })
        }
        m.addItem(submenuItem("Icon Spacing", gaps))

        m.addItem(.separator())
        m.addItem(ActionItem("Lock Position", checked: locked) { [weak self] in self?.store.locked.toggle() })
        let hideIDs = screenID.map { [$0] } ?? NSScreen.screens.map(\.stableID)
        let hideOn = hideIDs.allSatisfy { store.autoHide(for: $0) }
        let floating = screenID.map { store.placement(for: $0).edge == .free } ?? false
        let hideTitle = floating ? "Auto-Hide (pin to an edge to use)"
                                 : (screenID == nil ? "Auto-Hide (all screens)" : "Auto-Hide (this screen)")
        let hideItem = ActionItem(hideTitle, checked: hideOn && !floating, enabled: !floating) { [weak self] in
            self?.store.setAutoHide(!hideOn, for: hideIDs)
        }
        if screenID != nil {
            hideItem.keyEquivalent = "d"
            hideItem.keyEquivalentModifierMask = [.control, .option]
        }
        m.addItem(hideItem)
        m.addItem(ActionItem("Dock Mode (keep windows out from behind)", checked: store.dockMode) { [weak self] in
            self?.toggleDockMode()
        })
        m.addItem(ActionItem("Hide macOS Dock", checked: store.hideSystemDock) { [weak self] in
            guard let self else { return }
            self.setHideSystemDock(!self.store.hideSystemDock)
        })
        m.addItem(ActionItem("Bring Back macOS Dock When Q-Dock Quits", checked: store.restoreSystemDockOnQuit,
                             enabled: store.hideSystemDock) { [weak self] in self?.store.restoreSystemDockOnQuit.toggle() })
        m.addItem(ActionItem("Keep Above Other Windows", checked: store.alwaysOnTop || store.dockMode, enabled: !store.dockMode) {
            [weak self] in self?.store.alwaysOnTop.toggle()
        })
        m.addItem(ActionItem("Show Running Apps", checked: store.showRunning) { [weak self] in self?.store.showRunning.toggle() })
        m.addItem(ActionItem("Show Trash", checked: store.showTrash) { [weak self] in self?.store.showTrash.toggle() })
        m.addItem(.separator())
        m.addItem(ActionItem("Show on All Screens", checked: store.allScreens) { [weak self] in self?.store.allScreens.toggle() })
        m.addItem(ActionItem("Same Position on Every Screen", checked: store.syncPositions) { [weak self] in self?.store.syncPositions.toggle() })
        m.addItem(ActionItem("Launch at Login", checked: SMAppService.mainApp.status == .enabled) { self.toggleLoginItem() })
        m.addItem(.separator())
        m.addItem(ActionItem("Setup Assistant…") { Onboarding.shared.show() })
        m.addItem(ActionItem("Quit Q-Dock", key: "q") { NSApp.terminate(nil) })
        return m
    }

    func toggleDockMode() {
        if !store.dockMode && !AXIsProcessTrusted() {
            NSApp.activate(ignoringOtherApps: true)
            let a = NSAlert()
            a.messageText = "Dock Mode needs Accessibility access"
            a.informativeText = "Q-Dock moves and resizes other apps' windows so they don't sit behind an edge-pinned dock. "
                + "Allow Q-Dock in System Settings → Privacy & Security → Accessibility. Dock Mode starts working as soon as it's allowed."
            a.runModal()
        }
        store.dockMode.toggle()
    }

    @objc func statusClicked() {
        statusItem.menu = dockMenu(screenID: nil)
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    func addItems() {
        NSApp.activate(ignoringOtherApps: true)
        let p = NSOpenPanel()
        p.allowsMultipleSelection = true
        p.canChooseFiles = true
        p.canChooseDirectories = true
        p.directoryURL = URL(fileURLWithPath: "/Applications")
        p.prompt = "Add to Dock"
        if p.runModal() == .OK { store.add(p.urls) }
    }

    func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            let a = NSAlert()
            a.messageText = "Couldn't change the login item"
            a.informativeText = "\(error.localizedDescription)\n\nTip: move Q-Dock.app into your Applications folder first."
            a.runModal()
        }
    }
}

/// One-time copy of settings from the app's previous identity (PinDock, com.local.pindock).
func migrateLegacySettings() {
    let d = UserDefaults.standard
    guard d.object(forKey: "migratedFromPinDock") == nil else { return }
    d.set(true, forKey: "migratedFromPinDock")
    guard d.object(forKey: "items") == nil, d.object(forKey: "onboarded") == nil,
          let old = d.persistentDomain(forName: "com.local.pindock") else { return }
    for (k, v) in old where !k.hasPrefix("NS") { d.set(v, forKey: k) }
}

migrateLegacySettings()
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.delegate = AppController.shared
app.run()

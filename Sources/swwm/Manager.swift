//
//  Manager.swift
//  swwm
//
//  Created by Yesset Murat on 03.11.2026.
//

import AppKit
import os
import SwwmCore

let log = Logger(subsystem: "dev.swwm.swwm", category: "events")

/// Applies the World to real windows and turns events and commands into
/// World changes.
final class Manager {

    let world: World
    var onReload: () -> String? = { nil }               // error message when the config is not applied
    var onQuit: () -> Void = {}
    var onChange: () -> Void = {}                         // something the bar shows may have changed

    private(set) var windows: [WindowID: AXWindow] = [:]
    private var hidden: [WindowID: MonitorID] = [:]      // window -> display it is hidden on
    private var titles: [WindowID: String] = [:]           // cached for queries, kept by kAXTitleChanged
    let dock = DockClient()
    var dockModuleInstalled = false                        // set at start from DockModuleInstaller.isInstalled
    private var shadowNoticeShown = false
    var onShadowUnavailable: () -> Void = {}
    private var raised: Set<WindowID> = []                 // set to the floating level by swwm
    private var raisedChildren: [WindowID: pid_t] = [:]    // sheets and dialogs among them, by app
    private var levelNoticeShown = false
    var onLevelUnavailable: () -> Void = {}
    private var remembered: [WindowID: String] = [:]     // workspace of minimized/hidden windows
    private var rememberedFloating: Set<WindowID> = []     // of those, the floating ones
    private var saved: SavedWorkspaces?                    // from the last run, read at start
    private var opened: [WindowID: CGRect] = [:]           // where the app opened it, until the size check
    private var tilesByKind: [String: Bool] = [:]          // learned from the first window of each kind
    private var savePending = false
    /// Per login session: the temporary directory is cleared on reboot.
    private static let savedFile = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "swwm-workspaces.json")
    private var history = FocusHistory()
    var focused: WindowID? { history.current }
    private(set) var lastWarp = Date.distantPast         // when swwm last moved the cursor
    private let park = FocusPark()
    private var pendingFocus: [MonitorID: DispatchWorkItem] = [:]

    init(world: World) {
        self.world = world
    }

    private var settings: Settings { world.config.settings }

    // MARK: - Startup

    func start() {
        world.updateMonitors(Displays.current())
        saved = (try? Data(contentsOf: Self.savedFile)).flatMap { try? JSONDecoder().decode(SavedWorkspaces.self, from: $0) }
        for app in NSWorkspace.shared.runningApplications where app.isManageable {
            adopt(app)
        }
        if let saved { world.restore(saved) }
        layoutAll()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            for id in self?.windows.keys.map({ $0 }) ?? [] { self?.floatIfRefused(id) }
        }
        applyShadowAll()
        applyLevelAll()
        if let app = NSWorkspace.shared.frontmostApplication { appActivated(app) }
    }

    func adopt(_ app: NSRunningApplication) {
        for w in AXWindow.windows(of: app) {
            let f = w.frame
            track(w, near: CGPoint(x: f.midX, y: f.midY), adopting: true)
        }
    }

    /// Adds a window to the World: to its rule's workspace, else to the
    /// active workspace of the display at `point`. Dialogs, sheets and
    /// fullscreen windows are not managed.
    @discardableResult
    /// `adopting`: found at start, so the last run's saved state applies to it.
    func track(_ w: AXWindow, near point: CGPoint, adopting: Bool = false) -> Bool {
        guard windows[w.id] == nil, NSRunningApplication(processIdentifier: w.pid)?.isManageable == true,
              w.isStandard, w.level == 0 || (adopting && raisedLastRun(w)), !w.isFullScreen, !w.isMinimized else {
            log.debug("skip \(w.id, privacy: .public) \(w.appName, privacy: .public) role=\(w.element.attribute(kAXRoleAttribute) as String? ?? "-", privacy: .public) sub=\(w.element.attribute(kAXSubroleAttribute) as String? ?? "-", privacy: .public) level=\(w.level, privacy: .public) full=\(w.isFullScreen, privacy: .public) min=\(w.isMinimized, privacy: .public)")
            return false
        }
        // A new or newly shown native tab takes the tile of the tab it covers,
        // which drops out of the app's window list. No tab bar check: when a
        // tab closes, the next one is reported before the close, already alone.
        if let app = NSRunningApplication(processIdentifier: w.pid) {
            let listed = Set(AXWindow.windows(of: app).map(\.id))
            let f = w.frame
            func overlap(_ id: WindowID) -> CGFloat {
                let r = world.layoutFrame(of: id, gap: settings.gap)?.intersection(f) ?? .null
                return r.isNull ? 0 : r.width * r.height
            }
            if let covered = windows.values.filter({ $0.pid == w.pid && !listed.contains($0.id) && overlap($0.id) > 0 })
                .max(by: { overlap($0.id) < overlap($1.id) }) {
                takeOver(covered.id, by: w)
                return true
            }
        }
        let rule = world.config.rules.first { $0.matches(app: w.appName, title: w.title) }
        let floats = rule?.float == true || !w.isResizable || rememberedFloating.remove(w.id) != nil
            || (adopting && saved?.wasFloating(w.id, pid: w.pid) == true)
        let frame = w.frame
        let target = remembered.removeValue(forKey: w.id)
            ?? saved?.workspace(of: w.id, pid: w.pid).flatMap { world.workspace(named: $0)?.name }
            ?? rule?.workspace
            ?? world.monitor(at: point).flatMap(world.activeWorkspace(on:))
        guard let target else { return false }
        windows[w.id] = w
        titles[w.id] = w.title
        opened[w.id] = frame
        AppObserver.current?.watch(w)  // windows first seen on a focus change are not watched yet
        world.add(w.id, to: target, floatingFrame: floats ? frame : nil)
        applyShadow(w.id)
        applyLevel(w.id)
        return true
    }

    /// Native tabs are windows of their own and only the shown one is listed:
    /// a tile follows the shown tab of its group.
    private func takeOver(_ old: WindowID, by w: AXWindow) {
        log.debug("tab \(w.id, privacy: .public) takes over \(old, privacy: .public)")
        world.replace(old, with: w.id)
        windows[old] = nil
        titles[old] = nil
        if let m = hidden.removeValue(forKey: old) { hidden[w.id] = m }
        windows[w.id] = w
        titles[w.id] = w.title
        if focused == old { history.focused(w.id, at: Date()) }
        AppObserver.current?.watch(w)
        applyShadow(w.id)
        if raised.remove(old) != nil { dock.setLevel(old, WindowLevel.normal) }  // the tab left behind
        applyLevel(w.id)
        onChange()
        saveSoon()
    }

    /// The tab a closed tab leaves on screen: an unmanaged window of the same
    /// app in the closed window's place.
    private func nextTab(after id: WindowID) -> AXWindow? {
        guard let w = windows[id], let app = NSRunningApplication(processIdentifier: w.pid),
              let r = world.layoutFrame(of: id, gap: settings.gap) else { return nil }
        return AXWindow.windows(of: app).first {
            windows[$0.id] == nil && $0.isStandard && !$0.isMinimized && near($0.frame, r)
        }
    }

    /// Equal up to the rounding apps do (632.5 comes back as 633).
    private func near(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= 1 && abs(a.minY - b.minY) <= 1
            && abs(a.width - b.width) <= 1 && abs(a.height - b.height) <= 1
    }

    /// Writes where each window is, once per run-loop turn of changes.
    private func saveSoon() {
        guard !savePending else { return }
        savePending = true
        DispatchQueue.main.async { [self] in
            savePending = false
            let s = SavedWorkspaces(world: world, pids: windows.mapValues(\.pid))
            try? JSONEncoder().encode(s).write(to: Self.savedFile, options: .atomic)
        }
    }

    /// A floating window a crashed run left at the floating level: it is swwm's,
    /// not an app's panel.
    private func raisedLastRun(_ w: AXWindow) -> Bool {
        w.level == Int(WindowLevel.floating) && saved?.wasFloating(w.id, pid: w.pid) == true
    }

    /// Sets a window's shadow to what `window-shadow` wants, if anything.
    func applyShadow(_ id: WindowID) {
        let floating = world.workspace(containing: id)?.floating[id] != nil
        guard let want = shadowWanted(floating: floating, mode: settings.windowShadow) else { return }
        dock.setShadow(id, want) { [weak self] ok in
            guard let self, !ok, self.dockModuleInstalled, !self.shadowNoticeShown else { return }
            self.shadowNoticeShown = true
            self.onShadowUnavailable()
        }
    }

    func applyShadowAll() {
        for id in windows.keys { applyShadow(id) }
    }

    /// Floating windows stay above tiled ones: through the Dock module they
    /// get the floating window level, and the normal level once they tile.
    func applyLevel(_ id: WindowID) {
        let floating = world.workspace(containing: id)?.floating[id] != nil
        guard floating != raised.contains(id) else { return }
        if floating { raised.insert(id) } else { raised.remove(id) }
        if !floating, let pid = windows[id]?.pid { lowerChildren(of: pid) }
        if floating, let w = windows[id] {  // a sheet already open goes up with it
            let kids: [AXUIElement] = w.element.attribute(kAXChildrenAttribute) ?? []
            for k in kids where k.attribute(kAXRoleAttribute) == kAXSheetRole as String {
                childWindowAppeared(k, pid: w.pid)
            }
        }
        dock.setLevel(id, floating ? WindowLevel.floating : WindowLevel.normal) { [weak self] reply in
            guard let self, reply != .done else { return }
            if floating { self.raised.remove(id) }  // asked again on the next change or Dock restart
            // Unreachable is the shadow notice's case; turned down means an older payload.
            guard reply == .rejected, self.dockModuleInstalled, !self.levelNoticeShown else { return }
            self.levelNoticeShown = true
            self.onLevelUnavailable()
        }
    }

    func applyLevelAll() {
        for id in windows.keys { applyLevel(id) }
    }

    /// A sheet of a raised window, or a dialog swwm does not manage of an app
    /// with a raised window, would open under it: it goes up too. Closed ones
    /// drop out of `raised` here, so the set stays small.
    func childWindowAppeared(_ element: AXUIElement, pid: pid_t) {
        var id: CGWindowID = 0
        guard _AXUIElementGetWindow(element, &id) == .success, id != 0, windows[id] == nil, !raised.contains(id) else { return }
        if element.attribute(kAXRoleAttribute) == kAXSheetRole as String {
            var parent: CGWindowID = 0
            guard let p: AXUIElement = element.attribute(kAXParentAttribute),
                  _AXUIElementGetWindow(p, &parent) == .success, raised.contains(parent) else { return }
        } else {
            // Dialogs only: a standard window swwm turned down now may be managed
            // later (its subrole not ready yet) and must stay at the normal level.
            let subrole: String? = element.attribute(kAXSubroleAttribute)
            guard [kAXDialogSubrole as String, kAXSystemDialogSubrole as String].contains(subrole),
                  windows.values.contains(where: { $0.pid == pid && raised.contains($0.id) }),
                  AXWindow.layer(of: id) == 0 else { return }  // never system prompts or overlays
        }
        for gone in raisedChildren.keys where AXWindow.layer(of: gone) == nil {
            raisedChildren[gone] = nil
            raised.remove(gone)
        }
        log.debug("raise child \(id, privacy: .public) of pid \(pid, privacy: .public)")
        raised.insert(id)
        raisedChildren[id] = pid
        dock.setLevel(id, WindowLevel.floating) { [weak self] reply in
            guard reply != .done else { return }
            self?.raised.remove(id)
            self?.raisedChildren[id] = nil
        }
    }

    /// Sheets and dialogs of `pid` go back down once the app has no raised
    /// window left.
    private func lowerChildren(of pid: pid_t) {
        guard !windows.values.contains(where: { $0.pid == pid && raised.contains($0.id) }) else { return }
        for (id, owner) in raisedChildren where owner == pid {
            raisedChildren[id] = nil
            raised.remove(id)
            dock.setLevel(id, WindowLevel.normal)
        }
    }

    /// Removes a window; when it had focus, focus goes to another window of the same display.
    func untrack(_ id: WindowID, remember: Bool) {
        defer { onChange() }
        log.debug("untrack \(id, privacy: .public) focused=\(self.focused.map(String.init) ?? "nil", privacy: .public)")
        guard let w = windows[id] else { return }
        if remember, let ws = world.workspace(containing: id), let wm = world.monitor(of: ws.name) {
            remembered[id] = ws.name
            if ws.floating[id] != nil { rememberedFloating.insert(id) }
            // A hidden app's window parked off-screen must come back on screen
            // when the app unhides, even if swwm is gone by then.
            if hidden[id] != nil {
                let area = world.workArea(of: wm)
                w.setFrame(ws.floating[id].map { shownFloatingFrame($0, on: world.monitorInfo(wm)!, area: area) }
                    ?? ws.tree.frames(in: area, gap: settings.gap)[id] ?? area)
            }
        }
        // Minimized or hidden it lives on: back to the normal level, so it is
        // managed again when it returns.
        if raised.remove(id) != nil {
            if remember { dock.setLevel(id, WindowLevel.normal) }
            lowerChildren(of: w.pid)
        }
        let now = Date()
        let hadFocus = history.wasRecentlyFocused(id, now: now)
        history.removed(at: now)
        let m = world.remove(id)
        windows[id] = nil
        titles[id] = nil
        hidden[id] = nil
        opened[id] = nil
        guard let m else { return }
        layout(m)
        if hadFocus {
            history.focused(nil, at: now)
            refocus(m)
        }
    }

    // MARK: - Layout

    func layoutAll() {
        for m in world.monitors { layout(m.id) }
    }

    func layout(_ m: MonitorID) {
        defer { onChange(); saveSoon() }
        guard let info = world.monitorInfo(m), let activeName = world.activeWorkspace(on: m),
              let ws = world.workspace(named: activeName) else { return }
        let others = world.monitors.filter { $0.id != m }

        for name in world.workspaces(on: m) where name != activeName {
            guard let other = world.workspace(named: name) else { continue }
            for id in other.windows where hidden[id] != m {
                guard let w = windows[id] else { continue }
                if hidden[id] == nil, other.floating[id] != nil { other.floating[id] = w.frame }
                w.setPosition(hiddenOrigin(for: w.frame.size, on: info, others: others))
                hidden[id] = m
            }
        }

        let area = world.workArea(of: m)
        for (id, r) in ws.tree.frames(in: area, gap: settings.gap) where id != ws.zoomed {
            windows[id]?.setFrame(r)
            hidden[id] = nil
        }
        for (id, r) in ws.floating {
            let frame = shownFloatingFrame(r, on: info, area: area)
            guard hidden[id] != nil || frame != r else { continue }
            ws.floating[id] = frame
            windows[id]?.setFrame(frame)
            hidden[id] = nil
        }
        if let z = ws.zoomed, let w = windows[z] {
            w.setFrame(area)
            w.raise()
            hidden[z] = nil
        }
    }

    /// Puts every hidden window back on screen; called on quit.
    func restoreAll() {
        for (id, m) in hidden {
            guard let w = windows[id], let ws = world.workspace(containing: id) else { continue }
            // The display may be gone already (quit during a display change).
            let home = world.monitor(of: ws.name) ?? m
            guard let info = world.monitorInfo(home) else { continue }
            let area = world.workArea(of: home)
            w.setFrame(ws.floating[id].map { shownFloatingFrame($0, on: info, area: area) }
                ?? ws.tree.frames(in: area, gap: settings.gap)[id] ?? area)
        }
        hidden = [:]
        if settings.windowShadow != .on {
            dock.setShadowsSync(windows.keys.map { (id: $0, shadow: true) })
        }
        dock.setLevelsSync(raised.map { (id: $0, level: WindowLevel.normal) })
        raised = []
    }

    func displaysChanged() {
        world.updateMonitors(Displays.current())
        // Positions refer to the old arrangement: mark every hidden window as
        // hidden nowhere, so layout re-hides it without saving its off-screen
        // frame as a floating frame.
        for id in hidden.keys { hidden[id] = kCGNullDirectDisplay }
        layoutAll()
        // The focused window's workspace may have moved onto a display that shows another one.
        if let f = focused, !world.isVisible(f), let ws = world.workspace(containing: f),
           let m = world.monitor(of: ws.name) {
            focus(monitor: m)
        }
    }

    // MARK: - Focus

    /// The display with keyboard focus.
    var focusedMonitor: MonitorID? {
        if let f = focused, let ws = world.workspace(containing: f) { return world.monitor(of: ws.name) }
        return park.monitor ?? world.monitor(at: Displays.cursor)
    }

    func focus(_ id: WindowID, warp: Bool = true) {
        defer { onChange() }
        guard let w = windows[id] else { return }
        park.clear()
        w.focus()
        history.focused(id, at: Date())
        world.noteFocused(id)
        guard warp, settings.mouseFollowsFocus else { return }
        // A tile may lie under floating windows, which stay on top: the cursor
        // goes to a part of it that shows, or stays put when none does, else
        // the next mouse move would hand focus to the window above.
        let f = w.frame
        let covers = world.workspace(containing: id).map { ws in
            ws.tree.contains(id) ? ws.floating.keys.compactMap { windows[$0]?.frame } : []
        } ?? []
        let cursor = Displays.cursor
        guard !f.contains(cursor) || covers.contains(where: { $0.contains(cursor) }),
              let p = visiblePoint(of: f, under: covers) else { return }
        lastWarp = Date()
        CGWarpMouseCursorPosition(p)
    }

    /// Focuses the most recent window of display `m`, or parks focus on it.
    func focus(monitor m: MonitorID) {
        defer { onChange() }
        if let id = world.focusCandidate(on: m) {
            focus(id)
        } else if let info = world.monitorInfo(m) {
            history.focused(nil, at: Date())
            park.park(on: info)
            if settings.mouseFollowsFocus, !info.frame.contains(Displays.cursor) {
                lastWarp = Date()
                CGWarpMouseCursorPosition(CGPoint(x: info.frame.midX, y: info.frame.midY))
            }
        }
    }

    /// After a close, macOS activates some other app, maybe on another
    /// display. Wait for that, then put focus back on display `m`.
    private func refocus(_ m: MonitorID) {
        log.debug("refocus display \(m, privacy: .public)")
        pendingFocus[m]?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.pendingFocus[m] = nil
            self?.focus(monitor: m)
        }
        pendingFocus[m] = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: item)
    }

    /// Records focus changes made outside swwm (clicks, app switches).
    func windowFocused(_ id: WindowID) {
        defer { onChange() }
        log.debug("windowFocused \(id, privacy: .public) managed=\(self.windows[id] != nil, privacy: .public)")
        guard windows[id] != nil, focused != id else { return }
        let now = Date()
        history.focused(id, at: now)
        park.clear()
        world.noteFocused(id)
        // A window on a hidden workspace got focus (Dock click, app switch): show its
        // workspace, a moment later. Not around a close: that is macOS picking a
        // fallback app (on cmd-q before the quit is even reported), and the
        // pending refocus overrides it.
        guard let ws = world.workspace(containing: id), let m = world.monitor(of: ws.name),
              world.activeWorkspace(on: m) != ws.name else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + FocusHistory.grace) { [weak self] in
            guard let self, self.focused == id, self.pendingFocus.isEmpty,
                  self.history.autoShowAllowed(focusedAt: now),
                  let ws = self.world.workspace(containing: id), let m = self.world.monitor(of: ws.name),
                  self.world.activeWorkspace(on: m) != ws.name else { return }
            self.world.show(ws.name)
            self.layout(m)
            self.onChange()
        }
    }

    func appActivated(_ app: NSRunningApplication) {
        log.debug("appActivated \(app.localizedName ?? "?", privacy: .public)")
        let el = AXUIElementCreateApplication(app.processIdentifier)
        guard let win: AXUIElement = el.attribute(kAXFocusedWindowAttribute),
              let w = AXWindow(win, app: app) else { return }
        windowFocusChanged(w)
    }

    /// A focus change reported by an app. A window that was not manageable
    /// when it appeared (fullscreen, subrole not ready yet) gets another try.
    func windowFocusChanged(_ w: AXWindow) {
        if windows[w.id] == nil { windowCreated(w) }
        windowFocused(w.id)
    }

    // MARK: - Commands

    func run(_ command: Command) {
        switch command {
        case .focus(let d):
            if let n = neighborOfFocused(d, tiledOnly: false) { focus(n) }
        case .swap(let d):
            guard let f = focused, let ws = world.workspace(containing: f),
                  let n = neighborOfFocused(d, tiledOnly: true) else { return }
            ws.tree.swap(f, n)
            relayout(f)
        case .warp(let d):
            guard let f = focused, let ws = world.workspace(containing: f),
                  let n = neighborOfFocused(d, tiledOnly: true) else { return }
            ws.tree.warp(f, onto: n, from: opposite(d))
            relayout(f)
        case .focusMonitor(let d):
            if let m = focusedMonitor, let n = world.monitorNeighbor(of: m, d) { focus(monitor: n) }
        case .moveToMonitor(let d):
            guard let f = focused, let m = focusedMonitor, let n = world.monitorNeighbor(of: m, d),
                  let target = world.activeWorkspace(on: n) else { return }
            moveFocused(f, to: target)
        case .workspace(let name):
            show(name)
        case .moveToWorkspace(let name):
            if let f = focused { moveFocused(f, to: name) }
        case .workspaceNext, .workspacePrev:
            if let m = focusedMonitor, let name = world.step(on: m, forward: command == .workspaceNext) { show(name) }
        case .toggleFloat:
            toggleFloat()
        case .toggleZoom:
            guard let f = focused, let ws = world.workspace(containing: f), ws.tree.contains(f) else { return }
            ws.zoomed = ws.zoomed == f ? nil : f
            relayout(f)
        case .balance:
            guard let f = focused, let ws = world.workspace(containing: f) else { return }
            ws.tree.balance()
            relayout(f)
        case .mirror(let axis):
            guard let f = focused, let ws = world.workspace(containing: f),
                  let m = world.monitor(of: ws.name) else { return }
            ws.tree.mirror(axis, in: world.workArea(of: m))
            layout(m)
        case .exec(let line):
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = ["-c", line]
            try? p.run()
        case .reload:
            _ = onReload()
        case .quit:
            onQuit()
        }
    }

    /// Shows a workspace on its display and focuses that display.
    func show(_ name: String) {
        guard let m = world.monitor(of: name) else { return }
        if world.activeWorkspace(on: m) != name {
            world.show(name)
            layout(m)
        }
        focus(monitor: m)
    }

    private func moveFocused(_ id: WindowID, to name: String) {
        guard let from = world.workspace(containing: id), from.name != name,
              let fromMonitor = world.monitor(of: from.name) else { return }
        world.move(id, to: name)
        if let ws = world.workspace(named: name), let f = ws.floating[id],
           let m = world.monitor(of: name), m != fromMonitor {
            // A floating window keeps its size and lands centered on the new display.
            let area = world.workArea(of: m)
            ws.floating[id] = CGRect(x: area.midX - f.width / 2, y: area.midY - f.height / 2,
                                     width: f.width, height: f.height)
            hidden[id] = m  // forces layout to place it
        }
        layout(fromMonitor)
        guard let m = world.monitor(of: name) else { return }
        world.show(name)
        layout(m)
        focus(id)
    }

    private func toggleFloat() {
        guard let f = focused, let ws = world.workspace(containing: f), let m = world.monitor(of: ws.name) else { return }
        let wasFloating = ws.floating[f] != nil
        world.remove(f)
        if wasFloating {
            world.add(f, to: ws.name, floatingFrame: nil)
        } else {
            let a = world.workArea(of: m)
            let frame = a.insetBy(dx: a.width / 4, dy: a.height / 4)
            world.add(f, to: ws.name, floatingFrame: frame)
            windows[f]?.setFrame(frame)
            windows[f]?.raise()
        }
        layout(m)
        applyShadow(f)
        applyLevel(f)
        focus(f, warp: false)
    }

    private func relayout(_ id: WindowID) {
        if let ws = world.workspace(containing: id), let m = world.monitor(of: ws.name) { layout(m) }
    }

    private func neighborOfFocused(_ d: Direction, tiledOnly: Bool) -> WindowID? {
        guard let f = focused, let ws = world.workspace(containing: f), let m = world.monitor(of: ws.name) else {
            return nil
        }
        var frames = ws.tree.frames(in: world.workArea(of: m), gap: settings.gap)
        if !tiledOnly {
            for id in ws.floating.keys { frames[id] = windows[id]?.frame }
        } else if frames[f] == nil {
            return nil
        }
        return neighbor(of: f, d, in: frames)
    }

    private func opposite(_ d: Direction) -> Direction {
        switch d {
        case .left: .right
        case .right: .left
        case .up: .down
        case .down: .up
        }
    }

    // MARK: - Events

    func windowCreated(_ w: AXWindow) {
        // New windows open on the display under the cursor.
        let returning = remembered[w.id] != nil  // unminimized or unhidden: keeps its place
        guard track(w, near: Displays.cursor), let ws = world.workspace(containing: w.id), let m = world.monitor(of: ws.name) else { return }
        if !returning, ws.tree.contains(w.id), world.isVisible(w.id) {
            switch tilesByKind[kind(of: w)] {
            case true?: settle(w.id, on: m)
            case false?:
                opened[w.id] = nil
                makeFloating(w.id, frame: w.frame)
            case nil: place(w.id, attempt: 0)
            }
        } else {
            settle(w.id, on: m)
        }
    }

    /// Tiles a new window or floats it, without first showing it in a tile it
    /// cannot fill: a window that stretches one way only floats where it opened.
    /// One that takes no size change yet (opening animation, Ghostty setting
    /// up) stays where the app put it and is asked again; after that it tiles,
    /// and the later checks float it if it still refuses.
    private func place(_ id: WindowID, attempt: Int) {
        guard let w = windows[id], let ws = world.workspace(containing: id), ws.tree.contains(id),
              let m = world.monitor(of: ws.name), world.isVisible(id) else { return }
        let axes = w.resizableAxes()
        let waits = [0.03, 0.06, 0.1, 0.15]
        if axes.width != axes.height {
            tilesByKind[kind(of: w)] = false
            opened[id] = nil
            makeFloating(id, frame: w.frame)
        } else if !axes.width, attempt < waits.count {
            let wait = waits[attempt] - (attempt > 0 ? waits[attempt - 1] : 0)
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in self?.place(id, attempt: attempt + 1) }
        } else {
            if axes.width { tilesByKind[kind(of: w)] = true }
            settle(id, on: m)
        }
    }

    /// Windows of one kind tile or float alike, so the next one is placed at
    /// once, without the in-place size probe (it waits out opening animations).
    /// The full-screen button tells an app's main windows from its panels
    /// (Finder's browser windows from its Info windows).
    private func kind(of w: AXWindow) -> String {
        let button: AXUIElement? = w.element.attribute(kAXFullScreenButtonAttribute)
        return "\(w.appName)|\(button != nil)"
    }

    /// Puts a window in its place before the rest of the display, then checks
    /// it again: a fresh window may drop the size and keep only the position.
    private func settle(_ id: WindowID, on m: MonitorID) {
        if world.isVisible(id), let r = world.layoutFrame(of: id, gap: settings.gap) { windows[id]?.setFrame(r) }
        layout(m)
        for delay in [0.03, 0.08, 0.3] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.world.isVisible(id), let win = self.windows[id],
                      let r = self.world.layoutFrame(of: id, gap: self.settings.gap) else { return }
                if !self.near(win.frame, r) { win.setFrame(r) }
                if delay == 0.3 { self.floatIfRefused(id) }  // still the wrong size after the last try
            }
        }
    }

    /// A tiled window that does not take its tile's size (a fixed-size dialog)
    /// would overlap its neighbors: it floats instead. 20pt of slack for
    /// windows that size in steps.
    private func floatIfRefused(_ id: WindowID) {
        let start = opened.removeValue(forKey: id)
        guard let w = windows[id], world.isVisible(id), let ws = world.workspace(containing: id), ws.zoomed != id,
              let m = world.monitor(of: ws.name), let r = ws.tree.frames(in: world.workArea(of: m), gap: settings.gap)[id]
        else { return }
        let now = w.frame
        guard abs(now.width - r.width) > 20 || abs(now.height - r.height) > 20 else { return }
        tilesByKind[kind(of: w)] = false
        makeFloating(id, frame: start ?? now)
    }

    /// Floats a tiled window at `frame`: where the app opened it, as a tile
    /// may have stretched it the one way it can. Off the work area: centered.
    private func makeFloating(_ id: WindowID, frame f: CGRect) {
        guard let w = windows[id], let ws = world.workspace(containing: id), let m = world.monitor(of: ws.name),
              let info = world.monitorInfo(m) else { return }
        log.debug("float \(id, privacy: .public) \(w.appName, privacy: .public)")
        let frame = shownFloatingFrame(f, on: info, area: world.workArea(of: m))
        world.remove(id)
        world.add(id, to: ws.name, floatingFrame: frame)
        if w.frame != frame { w.setFrame(frame) }
        layout(m)
        applyShadow(id)
        applyLevel(id)
    }

    func windowGone(_ id: WindowID) {
        if let next = nextTab(after: id) { takeOver(id, by: next) } else { untrack(id, remember: false) }
    }

    func windowMinimized(_ id: WindowID) { untrack(id, remember: true) }

    func appHidden(_ pid: pid_t) {
        log.debug("appHidden \(pid, privacy: .public)")
        for (id, w) in windows where w.pid == pid { untrack(id, remember: true) }
    }

    func appTerminated(_ pid: pid_t) {
        log.debug("appTerminated \(pid, privacy: .public)")
        for (id, w) in windows where w.pid == pid { untrack(id, remember: false) }
    }

    func appShown(_ app: NSRunningApplication) {
        for w in AXWindow.windows(of: app) { windowCreated(w) }
    }

    // MARK: - Mouse support

    /// The topmost managed window under `p`, or nil when an unmanaged window is on top.
    func window(at p: CGPoint) -> WindowID? {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let me = Int(getpid())
        for info in list {
            guard let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: dict), r.contains(p) else { continue }
            // swwm's own bar is on top here: nothing under it takes focus.
            if (info[kCGWindowOwnerPID as String] as? Int) == me, (info[kCGWindowAlpha as String] as? Double ?? 1) > 0 {
                return nil
            }
            let id = (info[kCGWindowNumber as String] as? Int).map(WindowID.init)
            // Floating windows swwm raised, and their sheets, sit above layer 0.
            let layer = info[kCGWindowLayer as String] as? Int
            guard layer == 0 || (layer == Int(WindowLevel.floating) && id.map(raised.contains) == true) else { continue }
            // Hidden windows keep a sliver on screen; they must never take focus.
            return id.flatMap { windows[$0] != nil && hidden[$0] == nil ? $0 : nil }
        }
        return nil
    }

    /// True while the user is in a window swwm does not manage (a system prompt
    /// such as SecurityAgent's, a sheet, a launcher panel): focus-follows-mouse
    /// must not pull focus away from it.
    var focusInUnmanagedWindow: Bool {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid() else { return false }
        let el = AXUIElementCreateApplication(app.processIdentifier)
        guard let win: AXUIElement = el.attribute(kAXFocusedWindowAttribute) else { return false }
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(win, &id) == .success && windows[id] == nil
    }

    func setFrame(_ id: WindowID, _ r: CGRect) { windows[id]?.setFrame(r) }

    func appName(of id: WindowID) -> String? { windows[id]?.appName }

    /// From what swwm already knows: no AX round-trips, so a hung app cannot
    /// stall a query (and the event tap on the main thread).
    func windowInfo(_ id: WindowID) -> WindowInfo? {
        windows[id].map {
            WindowInfo(app: $0.appName, title: titles[id] ?? "", frame: world.layoutFrame(of: id, gap: settings.gap) ?? .zero)
        }
    }

    func titleChanged(_ id: WindowID, _ title: String) {
        if windows[id] != nil { titles[id] = title }
    }

    /// A CLI request. `quit` answers first and quits on the next turn, so the
    /// client still gets its reply.
    func handle(_ request: Request) -> Reply {
        switch request {
        case .query(.windows):
            return .ok(json(world.windowSnapshots(focused: focused, info: windowInfo)))
        case .query(.workspaces):
            return .ok(json(world.workspaceSnapshots()))
        case .query(.monitors):
            return .ok(json(world.monitorSnapshots(focusedMonitor: focusedMonitor)))
        case .command(.workspace(let name)) where world.workspace(named: name) == nil,
             .command(.moveToWorkspace(let name)) where world.workspace(named: name) == nil:
            return .error("unknown workspace '\(name)'")
        case .command(.quit):
            DispatchQueue.main.async { [self] in onQuit() }
            return .ok()
        case .command(.reload):
            return onReload().map { .error("config not applied: \($0)") } ?? .ok()
        case .command(let c):
            run(c)
            return .ok()
        }
    }

    func setPosition(_ id: WindowID, _ p: CGPoint) { windows[id]?.setPosition(p) }

    func frame(of id: WindowID) -> CGRect? { windows[id]?.frame }

    /// Ends a modifier+left drag: a tiled window dropped on another tiled
    /// window swaps with it, or joins the active workspace of the display it
    /// was dropped on.
    func dropped(_ id: WindowID, at p: CGPoint) {
        guard let ws = world.workspace(containing: id), let from = world.monitor(of: ws.name) else { return }
        if ws.floating[id] != nil {
            ws.floating[id] = windows[id]?.frame
            return
        }
        if let to = world.monitor(at: p), to != from, let target = world.activeWorkspace(on: to) {
            world.move(id, to: target)
            layout(from)
            layout(to)
            applyShadow(id)
            return
        }
        if let other = windowUnder(p, excluding: id), ws.tree.contains(other) {
            ws.tree.swap(id, other)
        }
        layout(from)
    }

    /// Ends a modifier+right drag on a tiled window.
    func resized(_ id: WindowID, by delta: CGSize) {
        guard let ws = world.workspace(containing: id), let m = world.monitor(of: ws.name) else { return }
        if ws.floating[id] != nil {
            ws.floating[id] = windows[id]?.frame
            return
        }
        ws.tree.resize(id, by: delta, in: world.workArea(of: m), gap: settings.gap)
        layout(m)
    }

    func isFloating(_ id: WindowID) -> Bool { world.workspace(containing: id)?.floating[id] != nil }

    private func windowUnder(_ p: CGPoint, excluding id: WindowID) -> WindowID? {
        guard let ws = world.workspace(containing: id), let m = world.monitor(of: ws.name) else { return nil }
        return ws.tree.frames(in: world.workArea(of: m), gap: settings.gap)
            .first { $0.key != id && $0.value.contains(p) }?.key
    }
}

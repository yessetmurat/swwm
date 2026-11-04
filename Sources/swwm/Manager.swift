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
    private var needsPlacement: Set<WindowID> = []         // the next layout moves these even where they look placed
    private var titles: [WindowID: String] = [:]           // cached for queries, kept by kAXTitleChanged
    let dock = DockClient()
    var dockModuleInstalled = false                        // set at start from DockModuleInstaller.isInstalled
    private var shadowNoticeShown = false
    var onShadowUnavailable: () -> Void = {}
    var levels = FloatingLevels()                          // windows swwm put at the floating level
    var levelNoticeShown = false
    var onLevelUnavailable: () -> Void = {}
    private var remembered = Remembered()                  // minimized windows and those of hidden apps
    private var saved: SavedWorkspaces?                    // from the last run, read at start
    private var opened: [WindowID: CGRect] = [:]           // where the app opened it, until the size check
    private var tilesByKind: [String: Bool] = [:]          // learned from the first window of each kind
    private var savePending = false
    /// Per login session: the temporary directory is cleared on reboot.
    private static let savedFile = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "swwm-workspaces.json")
    private var history = FocusHistory()
    var focused: WindowID? { history.current }
    private(set) var lastCursorMove = Date.distantPast   // when swwm last moved the cursor (a warp or its own click)
    private let park = FocusPark()
    private var parkGeneration = 0                       // a pending desktop click is dropped once this moves
    private var pendingPark: (info: MonitorInfo, points: [CGPoint], generation: Int)?
    private var leaving: Set<WindowID> = []                // hidden by swwm, until the window server has moved them
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
    /// `facts`: read already (on the AX thread); nil reads them here.
    func track(_ w: AXWindow, facts: WindowFacts? = nil, near point: CGPoint, adopting: Bool = false) -> Bool {
        guard windows[w.id] == nil, NSRunningApplication(processIdentifier: w.pid)?.isManageable == true else { return false }
        let facts = facts ?? WindowFacts(w)
        let level = w.level
        guard facts.isStandard, level == 0 || levels.isChild(w.id) || (adopting && raisedLastRun(w)),
              !facts.isFullScreen, !facts.isMinimized else {
            log.debug("skip \(w.id, privacy: .public) \(w.appName, privacy: .public) role=\(facts.role ?? "-", privacy: .public) sub=\(facts.subrole ?? "-", privacy: .public) level=\(level, privacy: .public) full=\(facts.isFullScreen, privacy: .public) min=\(facts.isMinimized, privacy: .public)")
            return false
        }
        // Raised before its app reported it, as an app's windows are while the
        // app has a floating one: from now on its own floating state decides.
        levels.adopt(w.id, pid: w.pid)
        // A new or newly shown native tab takes the tile of the tab it covers,
        // which drops out of the app's window list. No tab bar check: when a
        // tab closes, the next one is reported before the close, already alone.
        if let app = NSRunningApplication(processIdentifier: w.pid) {
            let listed = Set(AXWindow.windows(of: app).map(\.id))
            let covered = windows.values.filter { $0.pid == w.pid && !listed.contains($0.id) }
            if let old = tabSibling(of: w.frame, among: tileFrames(of: covered.map(\.id))) {
                takeOver(old, by: w)
                return true
            }
        }
        let rule = world.config.rules.first { $0.matches(app: w.appName, title: w.title) }
        let back = remembered.take(w.id)
        let floats = rule?.float == true || !w.isResizable || back?.floating == true
            || (adopting && saved?.wasFloating(w.id, pid: w.pid) == true)
        let frame = w.frame
        // A workspace a config reload dropped meanwhile is no place to come back to.
        let target = back.flatMap { world.workspace(named: $0.workspace)?.name }
            ?? saved?.workspace(of: w.id, pid: w.pid).flatMap { world.workspace(named: $0)?.name }
            ?? rule?.workspace
            ?? world.monitor(at: point).flatMap(world.activeWorkspace(on:))
        guard let target else { return false }
        windows[w.id] = w
        WindowServer.watch(Array(windows.keys))
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
        opened[old] = nil
        if let m = hidden.removeValue(forKey: old) { hidden[w.id] = m }
        windows[w.id] = w
        WindowServer.watch(Array(windows.keys))
        titles[w.id] = w.title
        if focused == old { history.focused(w.id, at: Date()) }
        AppObserver.current?.watch(w)
        applyShadow(w.id)
        send(levels.set(old, pid: w.pid, floating: false))  // the tab left behind
        applyLevel(w.id)
        onChange()
        saveSoon()
    }

    /// The tab a closed tab leaves on screen: an unmanaged window of the same
    /// app in the closed window's place.
    private func nextTab(after id: WindowID) -> AXWindow? {
        guard let w = windows[id], let app = NSRunningApplication(processIdentifier: w.pid),
              let r = world.shownFrame(of: id) else { return nil }
        let candidates = AXWindow.windows(of: app).filter { windows[$0.id] == nil && $0.isStandard && !$0.isMinimized }
        let next = tabSibling(of: r, among: Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0.frame) }))
        return candidates.first { $0.id == next }
    }

    /// Where these windows are when shown, for those swwm places.
    private func tileFrames(of ids: [WindowID]) -> [WindowID: CGRect] {
        Dictionary(uniqueKeysWithValues: ids.compactMap { id in world.shownFrame(of: id).map { (id, $0) } })
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

    /// Removes a window; when it had focus, focus goes to another window of the same display.
    func untrack(_ id: WindowID, remember: Bool) {
        defer { onChange() }
        log.debug("untrack \(id, privacy: .public) focused=\(self.focused.map(String.init) ?? "nil", privacy: .public)")
        guard let w = windows[id] else { return }
        if remember, let ws = world.workspace(containing: id) {
            remembered.remember(id, .init(workspace: ws.name, pid: w.pid, floating: ws.floating[id] != nil))
            // A hidden app's window parked off-screen must come back on screen
            // when the app unhides, even if swwm is gone by then.
            if hidden[id] != nil, let r = world.shownFrame(of: id) { w.setFrame(r) }
        }
        // Minimized or hidden it lives on: back to the normal level, so it is
        // managed again when it returns.
        send(remember ? levels.set(id, pid: w.pid, floating: false) : levels.gone(id))
        let now = Date()
        let hadFocus = history.wasRecentlyFocused(id, now: now)
        history.removed(at: now)
        let m = world.remove(id)
        windows[id] = nil
        WindowServer.watch(Array(windows.keys))
        titles[id] = nil
        hidden[id] = nil
        leaving.remove(id)
        needsPlacement.remove(id)
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
            for id in other.windows where hidden[id] != m || needsPlacement.contains(id) {
                guard let w = windows[id] else { continue }
                // Its frame is no floating frame when it is hidden already or
                // placed for an old display arrangement.
                let stale = needsPlacement.remove(id) != nil
                if hidden[id] == nil, !stale, other.floating[id] != nil { other.floating[id] = w.frame }
                if w.setPosition(hiddenOrigin(for: w.frame.size, on: info, others: others)) { leaving.insert(id) }
                hidden[id] = m
            }
        }

        let area = world.workArea(of: m)
        leaving.subtract(ws.windows)  // shown again before their moved event came
        for (id, r) in ws.tree.frames(in: area, gap: settings.gap) where id != ws.zoomed {
            windows[id]?.setFrame(r)
            hidden[id] = nil
            needsPlacement.remove(id)
        }
        for (id, r) in ws.floating {
            let frame = shownFloatingFrame(r, on: info, area: area)
            guard hidden[id] != nil || needsPlacement.remove(id) != nil || frame != r else { continue }
            ws.floating[id] = frame
            windows[id]?.setFrame(frame)
            hidden[id] = nil
        }
        if let z = ws.zoomed, let w = windows[z] {
            w.setFrame(area)
            w.raise()
            hidden[z] = nil
            needsPlacement.remove(z)
        }
    }

    /// Puts every hidden window back on screen; called on quit.
    func restoreAll() {
        for id in hidden.keys {
            // Nil when its display is gone already (quit during a display change).
            if let w = windows[id], let r = world.shownFrame(of: id) { w.setFrame(r) }
        }
        hidden = [:]
        if settings.windowShadow != .on {
            dock.setShadowsSync(windows.keys.map { (id: $0, shadow: true) })
        }
        dock.setLevelsSync(levels.removeAll().map { (id: $0.window, level: $0.level) })
    }

    func displaysChanged() {
        world.updateMonitors(Displays.current())
        // Positions refer to the old arrangement: layout places every hidden
        // window again, without saving its off-screen frame as a floating frame.
        needsPlacement.formUnion(hidden.keys)
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
        parkGeneration += 1
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
        lastCursorMove = Date()
        CGWarpMouseCursorPosition(p)
    }

    /// Focuses the most recent window of display `m`, or parks focus on it.
    func focus(monitor m: MonitorID) {
        defer { onChange() }
        if let id = world.focusCandidate(on: m) {
            focus(id)
        } else if let info = world.monitorInfo(m) {
            history.focused(nil, at: Date())
            // The user's key or click that led here is used up: focus moves
            // that follow swwm's own desktop click are not the user's.
            history.input(at: .distantPast)
            let area = world.workArea(of: m)
            let points = parkPoints(cursor: Displays.cursor, area: area, mouseFollowsFocus: settings.mouseFollowsFocus)
            if settings.mouseFollowsFocus, !info.frame.contains(Displays.cursor), let p = points.last {
                lastCursorMove = Date()
                CGWarpMouseCursorPosition(p)
            }
            parkGeneration += 1
            pendingPark = (info, points, parkGeneration)
            evaluatePark()
        }
    }

    /// The windows of the workspace just hidden may still be on screen: click
    /// Finder's desktop once the window server has moved the ones in the way
    /// (their moved events call this again); park without a click when
    /// something else covers every point.
    private func evaluatePark() {
        guard let pending = pendingPark else { return }
        guard pending.generation == parkGeneration else {  // focus went elsewhere meanwhile
            pendingPark = nil
            return
        }
        let onScreen = WindowServer.onScreen()
        let desktop = Int(CGWindowLevelForKey(.desktopIconWindow))
        for p in pending.points {
            switch parkStep(at: p, onScreen: onScreen, leaving: leaving, desktopLayer: desktop) {
            case .click:
                pendingPark = nil
                lastCursorMove = Date()  // the click puts the cursor there
                park.park(on: pending.info, desktopPoint: p)
                return
            case .wait:
                return
            case .noClick:
                continue
            }
        }
        pendingPark = nil
        park.park(on: pending.info, desktopPoint: nil)
    }

    /// The window server has a window where swwm or its app put it.
    func windowMoved(_ id: WindowID) {
        guard leaving.remove(id) != nil else { return }
        evaluatePark()
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
        parkGeneration += 1  // a pending desktop click must not take focus back
        park.clear()
        world.noteFocused(id)
        // Mouse follows focus whoever moved it (a new window, cmd-tab, a Dock
        // click); after a hover or a click the cursor is on the window already.
        // The tile, not the window's frame: a new window may not be there yet.
        if settings.mouseFollowsFocus, world.isVisible(id), let r = world.shownFrame(of: id),
           !r.contains(Displays.cursor) {
            lastCursorMove = now
            CGWarpMouseCursorPosition(CGPoint(x: r.midX, y: r.midY))
        }
        // A window on a hidden workspace got focus (Dock click, app switch): show its
        // workspace, a moment later. Not around a close: that is macOS picking a
        // fallback app (on cmd-q before the quit is even reported), and the
        // pending refocus overrides it.
        guard let ws = world.workspace(containing: id), let m = world.monitor(of: ws.name),
              world.activeWorkspace(on: m) != ws.name else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + FocusHistory.grace) { [weak self] in
            guard let self, self.focused == id, self.pendingFocus.isEmpty,
                  let ws = self.world.workspace(containing: id), let m = self.world.monitor(of: ws.name),
                  self.world.activeWorkspace(on: m) != ws.name else { return }
            guard self.history.autoShowAllowed(focusedAt: now) else {
                // macOS, not the user, put focus on a hidden window: back to
                // what the user sees under the mouse.
                self.focus(monitor: self.world.monitor(at: Displays.cursor) ?? m)
                return
            }
            self.world.show(ws.name)
            self.layout(m)
            self.onChange()
        }
    }

    /// The focused window of the app now frontmost; read here, at start only.
    /// Later activations come from the AX thread as `windowFocusChanged`.
    func appActivated(_ app: NSRunningApplication) {
        log.debug("appActivated \(app.localizedName ?? "?", privacy: .public)")
        let el = AXUIElementCreateApplication(app.processIdentifier)
        guard let win: AXUIElement = el.attribute(kAXFocusedWindowAttribute),
              let w = AXWindow(win, app: app) else { return }
        windowFocusChanged(w, facts: WindowFacts(w))
    }

    /// A focus change reported by an app. A window that was not manageable
    /// when it appeared (fullscreen, subrole not ready yet) gets another try.
    func windowFocusChanged(_ w: AXWindow, facts: WindowFacts) {
        if windows[w.id] == nil { windowCreated(w, facts: facts) }
        // Focus moved to a window swwm does not manage on another display:
        // the parked display no longer has the keyboard.
        if windows[w.id] == nil, let m = park.monitor, let b = WindowServer.window(w.id)?.bounds,
           world.monitor(at: CGPoint(x: b.midX, y: b.midY)) != m {
            park.clear()
        }
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
            needsPlacement.insert(id)
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

    func windowCreated(_ w: AXWindow, facts: WindowFacts) {
        // New windows open on the display under the cursor.
        let returning = remembered.contains(w.id)  // unminimized or unhidden: keeps its place
        guard track(w, facts: facts, near: Displays.cursor), let ws = world.workspace(containing: w.id), let m = world.monitor(of: ws.name) else { return }
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
              let m = world.monitor(of: ws.name), world.isVisible(id) else {
            opened[id] = nil  // floated, moved or gone meanwhile: no size check follows
            return
        }
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
        if world.isVisible(id), let r = world.shownFrame(of: id) { windows[id]?.setFrame(r) }
        layout(m)
        for delay in [0.03, 0.08, 0.3] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.world.isVisible(id), let win = self.windows[id],
                      let r = self.world.shownFrame(of: id) else { return }
                if !near(win.frame, r) { win.setFrame(r) }
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
              ws.tree.contains(id), let r = world.shownFrame(of: id) else { return }
        let now = w.frame
        guard !near(CGRect(origin: .zero, size: now.size), CGRect(origin: .zero, size: r.size), tolerance: 20) else { return }
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
        remembered.forget(pid: pid)
    }

    /// An app's windows, listed on the AX thread; known ones are skipped.
    func rescan(_ found: [(window: AXWindow, facts: WindowFacts)]) {
        for f in found { windowCreated(f.window, facts: f.facts) }
    }

    // MARK: - Mouse support

    /// The topmost managed window under `p`, or nil when an unmanaged window is on top.
    func window(at p: CGPoint) -> WindowID? {
        let me = getpid()
        for w in WindowServer.onScreen(excludingDesktop: true) where w.bounds.contains(p) {
            // swwm's own bar is on top here: nothing under it takes focus.
            if w.pid == me, w.alpha > 0 { return nil }
            // Floating windows swwm raised, and their sheets, sit above layer 0.
            guard w.layer == 0 || (w.layer == Int(WindowLevel.floating) && levels.isRaised(w.id)) else { continue }
            // Hidden windows keep a sliver on screen; they must never take focus.
            return windows[w.id] != nil && hidden[w.id] == nil ? w.id : nil
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

    func pid(of id: WindowID) -> pid_t? { windows[id]?.pid }

    /// A click or key press: focus that follows it is the user's doing.
    func noteInput() { history.input(at: Date()) }

    /// From what swwm already knows: no AX round-trips, so a hung app cannot
    /// stall a query (and the event tap on the main thread).
    func windowInfo(_ id: WindowID) -> WindowInfo? {
        windows[id].map {
            WindowInfo(app: $0.appName, title: titles[id] ?? "", frame: world.shownFrame(of: id) ?? .zero)
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
        guard let ws = world.workspace(containing: id) else { return nil }
        return ws.tree.windows.first { $0 != id && world.shownFrame(of: $0)?.contains(p) == true }
    }
}

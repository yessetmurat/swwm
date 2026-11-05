//
//  Manager.swift
//  swwm
//
//  Created by Yesset Murat on 03.11.2026.
//

import AppKit
import SwwmCore

/// Applies the World to real windows and turns events and commands into
/// World changes.
final class Manager: AppEvents {

    let world: World
    var onReload: () -> String? = { nil }               // error message when the config is not applied
    var onQuit: () -> Void = {}
    var onChange: () -> Void = {}                         // something the bar shows may have changed

    private(set) var windows: [WindowID: ManagedWindow] = [:]
    weak var connections: Connections?
    private var hidden: [WindowID: MonitorID] = [:]      // window -> display it is hidden on
    private var needsPlacement: Set<WindowID> = []         // the next layout moves these even where they look placed
    private var startPids: Set<pid_t> = []                 // apps running when swwm started
    private var joinedPids: Set<pid_t> = []                // of those, the ones that reported their windows
    private var touched: Set<String> = []                  // workspaces whose tiles changed since start
    private(set) var finderHasDesktop = true               // Finder lists a desktop (`CreateDesktop` not off)
    let dock = DockClient()
    var dockModuleInstalled = false                        // set at start from DockModuleInstaller.isInstalled
    private var shadowNoticeShown = false
    private var dockAwaited = false                        // asking until the Dock module answers
    var onShadowUnavailable: () -> Void = {}
    var levels = FloatingLevels()                          // windows swwm put at the floating level
    var levelNoticeShown = false
    var onLevelUnavailable: () -> Void = {}
    var remembered = Remembered()                  // minimized windows and those of hidden apps
    private var saved: SavedWorkspaces?                    // from the last run, read at start
    var opened: [WindowID: CGRect] = [:]                   // where the app opened it, until the size check
    var tilesByKind: [String: Bool] = [:]                  // learned from the first window of each kind
    var settling: Set<WindowID> = []                       // new, until the size check: their own resizes are undone
    var zooming: [WindowID: Bool] = [:]                    // title-bar double-clicked tiles; true once swwm put one back
    private var savePending = false
    private var lastSaved: Data?                           // what the file holds
    /// Per login session: the temporary directory is cleared on reboot.
    private static let savedFile = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "swwm-workspaces.json")
    private var history = FocusHistory()
    var focused: WindowID? { history.current }
    private(set) var lastCursorMove = Date.distantPast { didSet { publishSoon() } }  // a warp or swwm's own click
    var onPublish: ((TapView) -> Void)?                   // hands the event tap what it decides from
    private var publishPending = false
    private let park = FocusPark()
    private var parkGeneration = 0                       // a pending desktop click is dropped once this moves
    private var pendingPark: (info: MonitorInfo, points: [CGPoint], generation: Int)?
    private var leaving: Set<WindowID> = []                // hidden by swwm, until the window server has moved them
    private var pendingFocus: [MonitorID: DispatchWorkItem] = [:]
    // Workaround: after a close macOS activates some other app, with no event
    // saying it is done; swwm puts focus back after it.
    private static let refocusWait = 0.05

    init(world: World) {
        self.world = world
    }

    var settings: Settings { world.config.settings }

    // MARK: - Startup

    func start() {
        world.updateMonitors(Displays.current())

        saved = (try? Data(contentsOf: Self.savedFile)).flatMap { try? JSONDecoder().decode(SavedWorkspaces.self, from: $0) }

        // The windows join as their apps report them (`appWindows`).
        if let saved { world.restoreActive(saved) }

        layoutAll()
    }

    /// The apps running at start: their windows get the last run's places.
    func startApps(_ pids: Set<pid_t>) { startPids = pids }

    private var pendingStart: Set<pid_t> { startPids.subtracting(joinedPids) }

    /// Adds a window to the World as `trackDecision` says. `adopting`: its app
    /// ran when swwm started, so the last run's saved state applies to it.
    @discardableResult
    func track(_ s: AppWindow, adopting: Bool) -> Bool {
        guard windows[s.id] == nil, let app = NSRunningApplication(processIdentifier: s.pid), app.isManageable else {
            return false
        }

        let appWindows = windows.values.filter { $0.pid == s.pid }
        let context = TrackContext(
            appFrames: Dictionary(uniqueKeysWithValues: appWindows.map { ($0.id, $0.frame) }),
            isChild: levels.isChild(s.id),
            adopting: adopting,
            appHidden: app.isHidden,
            point: adopting ? CGPoint(x: s.frame.midX, y: s.frame.midY) : Displays.cursor
        )

        switch trackDecision(
            s,
            world: world,
            context: context,
            remembered: &remembered,
            saved: saved
        ) {
        case .skip:
            log.debug("skip \(s.id, privacy: .public) \(s.app, privacy: .public) role=\(s.role ?? "-", privacy: .public) sub=\(s.subrole ?? "-", privacy: .public) level=\(s.layer, privacy: .public) full=\(s.isFullScreen, privacy: .public) min=\(s.isMinimized, privacy: .public)")
            return false
        case .takeOver(let old):
            // Raised before its app reported it, as an app's windows are while the
            // app has a floating one: from now on its own floating state decides.
            levels.adopt(s.id, pid: s.pid)
            takeOver(old, by: s)
            return true
        case .manage(let target, let floating):
            levels.adopt(s.id, pid: s.pid)
            windows[s.id] = ManagedWindow(s)
            WindowServer.watch(Array(windows.keys))
            opened[s.id] = s.frame
            world.add(s.id, to: target, floatingFrame: floating ? s.frame : nil)
            if !adopting { touched.insert(target) }
            applyShadow(s.id)
            applyLevel(s.id)
            return true
        }
    }

    /// Native tabs are windows of their own and only the shown one is listed:
    /// a tile follows the shown tab of its group.
    private func takeOver(_ old: WindowID, by w: AppWindow) {
        log.debug("tab \(w.id, privacy: .public) takes over \(old, privacy: .public)")

        world.replace(old, with: w.id)
        windows[old] = nil
        opened[old] = nil
        if let m = hidden.removeValue(forKey: old) { hidden[w.id] = m }
        if let z = zooming.removeValue(forKey: old) { zooming[w.id] = z }
        windows[w.id] = ManagedWindow(w)
        WindowServer.watch(Array(windows.keys))
        if focused == old { history.focused(w.id, at: Date()) }

        applyShadow(w.id)
        send(levels.set(old, pid: w.pid, floating: false))  // the tab left behind
        applyLevel(w.id)

        onChange()
        saveSoon()
    }

    /// The tab a closed tab leaves on screen: an unmanaged window of the same
    /// app with the closed window's frame.
    private func nextTab(after id: WindowID, listed: [AppWindow]) -> AppWindow? {
        guard let r = windows[id]?.frame else {
            return nil
        }

        let candidates = listed.filter { windows[$0.id] == nil && $0.isStandard && !$0.isMinimized }
        let next = tabSibling(of: r, among: Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0.frame) }))
        return candidates.first { $0.id == next }
    }

    /// Writes where each window is, once per run-loop turn of changes.
    private func saveSoon() {
        guard !savePending else {
            return
        }

        savePending = true
        DispatchQueue.main.async { [self] in
            savePending = false
            var s = SavedWorkspaces(world: world, pids: windows.mapValues(\.pid))
            // Apps still starting keep their places from the last run.
            if let saved, !pendingStart.isEmpty {
                s = s.merging(saved, pending: Set(pendingStart.map { Int32($0) }),
                              untouched: Set(world.workspaceNames).subtracting(touched))
            }

            // Most layouts change nothing that is saved: no write then.
            guard let data = try? JSONEncoder().encode(s), data != lastSaved else {
                return
            }
            lastSaved = data
            try? data.write(to: Self.savedFile, options: .atomic)
        }
    }

    /// Sets a window's shadow to what `window-shadow` wants, if anything.
    func applyShadow(_ id: WindowID) {
        let floating = world.workspace(containing: id)?.floating[id] != nil
        guard let want = shadowWanted(floating: floating, mode: settings.windowShadow) else {
            return
        }

        dock.setShadow(id, want) { [weak self] reply in
            guard let self, reply == .unreachable, self.dockModuleInstalled else {
                return
            }

            self.awaitDock()
        }
    }

    func applyShadowAll() {
        for id in windows.keys { applyShadow(id) }
    }

    /// The Dock module is not there yet (a new Dock, or swwm started before
    /// the loader injected it): every window gets its shadow and level once
    /// it answers. The notice is for a module that never does.
    func awaitDock() {
        guard !dockAwaited else {
            return
        }

        dockAwaited = true
        dock.whenReachable { [weak self] reached in
            guard let self else {
                return
            }

            self.dockAwaited = false

            if reached {
                self.applyShadowAll()
                self.applyLevelAll()  // windows an older payload turned down, after a re-install
            } else if self.dockModuleInstalled, !self.shadowNoticeShown {
                self.shadowNoticeShown = true
                self.onShadowUnavailable()
            }
        }
    }

    /// Removes a window; when it had focus, focus goes to another window of the same display.
    func untrack(_ id: WindowID, remember: Bool) {
        defer { onChange() }
        log.debug("untrack \(id, privacy: .public) focused=\(self.focused.map(String.init) ?? "nil", privacy: .public)")
        guard let w = windows[id] else {
            return
        }

        if remember, let ws = world.workspace(containing: id) {
            remembered.remember(id, .init(workspace: ws.name, pid: w.pid, floating: ws.floating[id] != nil))
            // A hidden app's window parked off-screen must come back on screen
            // when the app unhides, even if swwm is gone by then.
            if hidden[id] != nil, let r = world.shownFrame(of: id) { setFrame(id, r) }
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
        hidden[id] = nil
        leaving.remove(id)
        needsPlacement.remove(id)
        opened[id] = nil
        settling.remove(id)
        zooming[id] = nil

        guard let m else {
            return
        }

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
        defer {
            onChange()
            saveSoon()
        }
        guard let info = world.monitorInfo(m), let activeName = world.activeWorkspace(on: m),
              let ws = world.workspace(named: activeName) else {
            return
        }

        let others = world.monitors.filter { $0.id != m }

        for name in world.workspaces(on: m) where name != activeName {
            guard let other = world.workspace(named: name) else {
                continue
            }

            for id in other.windows where hidden[id] != m || needsPlacement.contains(id) {
                guard let w = windows[id] else {
                    continue
                }

                // Its frame is no floating frame when it is hidden already or
                // placed for an old display arrangement.
                let stale = needsPlacement.remove(id) != nil
                if hidden[id] == nil, !stale, other.floating[id] != nil { other.floating[id] = w.frame }
                setPosition(id, hiddenOrigin(for: w.frame.size, on: info, others: others))
                leaving.insert(id)  // until its moved event, or the app turns the write down
                hidden[id] = m
            }
        }

        let area = world.workArea(of: m)
        leaving.subtract(ws.windows)  // shown again before their moved event came

        for (id, r) in ws.tree.frames(in: area, gap: settings.gap) where id != ws.zoomed {
            setFrame(id, r)
            hidden[id] = nil
            needsPlacement.remove(id)
        }

        for (id, r) in ws.floating {
            let frame = shownFloatingFrame(r, on: info, area: area)
            guard hidden[id] != nil || needsPlacement.remove(id) != nil || frame != r else {
                continue
            }

            ws.floating[id] = frame
            setFrame(id, frame)
            hidden[id] = nil
        }

        if let z = ws.zoomed, let w = windows[z] {
            setFrame(z, area)
            connections?.connection(w.pid)?.raise(z)
            hidden[z] = nil
            needsPlacement.remove(z)
        }
    }

    /// Puts every hidden window back on screen; called on quit.
    func restoreAll() {
        for id in hidden.keys {
            // Nil when its display is gone already (quit during a display change).
            if let r = world.shownFrame(of: id) { setFrame(id, r) }
        }

        hidden = [:]
        connections?.flush()

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
        guard let w = windows[id] else {
            return
        }

        parkGeneration += 1
        park.clear()
        if let c = connections { c.connection(w.pid)?.focus(id, ticket: c.focusTicket.next()) }

        history.focused(id, at: Date())
        world.noteFocused(id)

        guard warp, settings.mouseFollowsFocus else {
            return
        }

        // A tile may lie under floating windows, which stay on top: the cursor
        // goes to a part of it that shows, or stays put when none does, else
        // the next mouse move would hand focus to the window above.
        guard let f = world.shownFrame(of: id) else {
            return
        }

        let covers = world.workspace(containing: id).map { ws in ws.tree.contains(id) ? Array(ws.floating.values) : [] } ?? []
        let cursor = Displays.cursor

        guard !f.contains(cursor) || covers.contains(where: { $0.contains(cursor) }),
              let p = visiblePoint(of: f, under: covers) else {
            return
        }

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
            focusMovedOn()

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
        guard let pending = pendingPark else {
            return
        }

        guard pending.generation == parkGeneration else {  // focus went elsewhere meanwhile
            pendingPark = nil
            return
        }

        let onScreen = WindowServer.onScreen()
        let desktop = Int(CGWindowLevelForKey(.desktopIconWindow))

        for p in pending.points {
            switch parkStep(
                at: p,
                onScreen: onScreen,
                leaving: leaving,
                desktopLayer: desktop
            ) {
            case .click:
                pendingPark = nil
                lastCursorMove = Date()  // the click puts the cursor there
                park.park(on: pending.info, desktopPoint: finderHasDesktop ? p : nil)
                return
            case .wait:
                return
            case .noClick:
                continue
            }
        }

        pendingPark = nil
        focusInUnmanagedWindow = false  // swwm holds focus itself
        park.park(on: pending.info, desktopPoint: nil)
    }

    /// The window server has a window where swwm or its app put it.
    func windowMoved(_ id: WindowID) {
        guard leaving.remove(id) != nil else {
            return
        }

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
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.refocusWait, execute: item)
    }

    /// Records focus changes made outside swwm (clicks, app switches).
    func windowFocused(_ id: WindowID) {
        defer { onChange() }
        log.debug("windowFocused \(id, privacy: .public) managed=\(self.windows[id] != nil, privacy: .public)")
        guard windows[id] != nil, focused != id else {
            return
        }

        focusMovedOn()

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
              world.activeWorkspace(on: m) != ws.name else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + FocusHistory.grace) { [weak self] in
            guard let self,
                  self.focused == id,
                  self.pendingFocus.isEmpty,
                  let ws = self.world.workspace(containing: id),
                  let m = self.world.monitor(of: ws.name),
                  self.world.activeWorkspace(on: m) != ws.name else {
                return
            }

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

    /// The app now frontmost has no focused window.
    func noFocusedWindow() {
        focusMovedOn()
        focusInUnmanagedWindow = false
    }

    /// A focus change reported by an app. A window that was not manageable
    /// when it appeared (fullscreen, subrole not ready yet) gets another try.
    func windowFocusChanged(_ w: AppWindow) {
        // An app still starting reports its windows first, with their last places.
        if windows[w.id] == nil, !pendingStart.contains(w.pid) { windowCreated(w) }

        guard focusReportIsFocus(from: w.pid, frontmost: NSWorkspace.shared.frontmostApplication?.processIdentifier) else {
            return
        }

        focusInUnmanagedWindow = windows[w.id] == nil
        if focusInUnmanagedWindow { focusMovedOn() }

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
                  let n = neighborOfFocused(d, tiledOnly: true) else {
                return
            }

            touched.insert(ws.name)
            ws.tree.swap(f, n)
            relayout(f)
        case .warp(let d):
            guard let f = focused, let ws = world.workspace(containing: f),
                  let n = neighborOfFocused(d, tiledOnly: true) else {
                return
            }

            touched.insert(ws.name)
            ws.tree.warp(f, onto: n, from: opposite(d))
            relayout(f)
        case .focusMonitor(let d):
            if let m = focusedMonitor, let n = world.monitorNeighbor(of: m, d) { focus(monitor: n) }
        case .moveToMonitor(let d):
            guard let f = focused,
                  let m = focusedMonitor,
                  let n = world.monitorNeighbor(of: m, d),
                  let target = world.activeWorkspace(on: n) else {
                return
            }

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
            guard let f = focused, let ws = world.workspace(containing: f), ws.tree.contains(f) else {
                return
            }

            ws.zoomed = ws.zoomed == f ? nil : f
            relayout(f)
        case .balance:
            guard let f = focused, let ws = world.workspace(containing: f) else {
                return
            }

            touched.insert(ws.name)
            ws.tree.balance()
            relayout(f)
        case .mirror(let axis):
            guard let f = focused, let ws = world.workspace(containing: f),
                  let m = world.monitor(of: ws.name) else {
                return
            }

            touched.insert(ws.name)
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
        guard let m = world.monitor(of: name) else {
            return
        }

        if world.activeWorkspace(on: m) != name {
            world.show(name)
            layout(m)
        }

        focus(monitor: m)
    }

    private func moveFocused(_ id: WindowID, to name: String) {
        guard let from = world.workspace(containing: id), from.name != name,
              let fromMonitor = world.monitor(of: from.name) else {
            return
        }

        world.move(id, to: name)
        touched.formUnion([from.name, name])

        if let ws = world.workspace(named: name), let f = ws.floating[id],
           let m = world.monitor(of: name), m != fromMonitor {
            // A floating window keeps its size and lands centered on the new display.
            let area = world.workArea(of: m)
            ws.floating[id] = CGRect(
                x: area.midX - f.width / 2,
                y: area.midY - f.height / 2,
                width: f.width,
                height: f.height
            )
            needsPlacement.insert(id)
        }

        layout(fromMonitor)

        guard let m = world.monitor(of: name) else {
            return
        }

        world.show(name)
        layout(m)
        focus(id)
    }

    private func toggleFloat() {
        guard let f = focused, let ws = world.workspace(containing: f), let m = world.monitor(of: ws.name) else {
            return
        }

        let wasFloating = ws.floating[f] != nil
        touched.insert(ws.name)
        world.remove(f)

        if wasFloating {
            world.add(f, to: ws.name, floatingFrame: nil)
        } else {
            let a = world.workArea(of: m)
            let frame = a.insetBy(dx: a.width / 4, dy: a.height / 4)
            world.add(f, to: ws.name, floatingFrame: frame)
            setFrame(f, frame)
            if let w = windows[f] { connections?.connection(w.pid)?.raise(f) }
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

    func windowGone(_ id: WindowID, listed: [AppWindow]) {
        if let next = nextTab(after: id, listed: listed) { takeOver(id, by: next) } else { untrack(id, remember: false) }
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
        startPids.remove(pid)
    }

    /// An app's windows: on connecting (`adopting` for an app that ran when
    /// swwm started) and on unhide. Known ones are skipped.
    func appWindows(_ found: [AppWindow], pid: pid_t, adopting: Bool) {
        if NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.apple.finder" {
            finderHasDesktop = found.contains { $0.isFinderDesktop }
        }

        guard adopting else {
            return found.forEach(windowCreated)
        }

        joinedPids.insert(pid)
        var shown: Set<MonitorID> = []
        for w in found where track(w, adopting: true) {
            guard let ws = world.workspace(containing: w.id), let m = world.monitor(of: ws.name) else {
                continue
            }

            // Its workspace's tiles as the last run left them, while nobody changed them since.
            if !touched.contains(ws.name), let shape = saved?.shape(of: ws.name) { ws.tree.restore(shape) }
            shown.insert(m)
        }

        shown.forEach(layout)

        let adopted = found.map(\.id).filter { windows[$0] != nil }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.startRefusalCheck) { [weak self] in
            for id in adopted { self?.floatIfRefused(id) }
        }

        if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid { connections?.connection(pid)?.readFocus() }
    }

    func windowAppeared(_ w: AppWindow) { windowCreated(w) }

    func focusChanged(_ w: AppWindow?, pid: pid_t) {
        if let w { return windowFocusChanged(w) }
        // A background app closing its last window says nothing about focus.
        if focusReportIsFocus(from: pid, frontmost: NSWorkspace.shared.frontmostApplication?.processIdentifier) { noFocusedWindow() }
    }

    /// The app did not take a write: the window stays where it was, so a
    /// park waiting for it to leave must not wait any longer.
    func writeFailed(_ id: WindowID) {
        guard leaving.remove(id) != nil else {
            return
        }

        evaluatePark()
    }

    /// An app that left writes unanswered (stopped, or busy for long)
    /// answers again: its windows go where their workspaces want them.
    func appAnswered(_ ids: Set<WindowID>) {
        let mine = ids.filter { windows[$0] != nil }
        needsPlacement.formUnion(mine)
        Set(mine.compactMap { world.workspace(containing: $0).flatMap { world.monitor(of: $0.name) } }).forEach(layout)
    }

    /// Focus asked for from the pointer (a hover or a modifier press), checked
    /// against the current state: the tap decided from a copy.
    func pointerFocus(_ id: WindowID, hover: Bool) {
        let shown: Set<WindowID> = windows[id] != nil && world.isVisible(id) && hidden[id] == nil ? [id] : []

        if hover {
            let takesFocus = hoverTakesFocus(
                id,
                focused: focused,
                shown: shown,
                focusUnmanaged: focusInUnmanagedWindow,
                lastCursorMove: lastCursorMove,
                now: Date()
            )
            guard takesFocus else {
                return
            }
        } else {
            guard shown.contains(id) else {
                return
            }
        }

        focus(id, warp: false)
    }

    /// Focus moved somewhere swwm did not send it: a focus command still
    /// waiting for its app is stale.
    private func focusMovedOn() { _ = connections?.focusTicket.next() }

    /// The window's frame as its app has it now, for decisions made after
    /// something moved it; `reply` runs on main.
    func readFrame(_ id: WindowID, reply: @escaping (CGRect?) -> Void) {
        guard let w = windows[id], let c = connections?.connection(w.pid) else {
            return reply(nil)
        }

        c.readFrame(id) { [weak self] f in
            if let f {
                self?.windows[id]?.frame = f
                self?.publishSoon()
            }
            reply(f)
        }
    }

    /// The window server moved or resized a managed window: learn its frame;
    /// one still settling that its app resized gets its tile back.
    func refreshFrame(_ id: WindowID) {
        guard windows[id] != nil else {
            return
        }

        readFrame(id) { [weak self] _ in self?.windowResized(id) }
    }

    // MARK: - Mouse support

    /// True while the user is in a window swwm does not manage (a system prompt
    /// such as SecurityAgent's, a sheet, a launcher panel): focus-follows-mouse
    /// must not pull focus away from it. Kept from the focus reports.
    private(set) var focusInUnmanagedWindow = false { didSet { publishSoon() } }

    /// Gives the event tap a fresh `TapView`, once per run-loop turn of
    /// changes.
    func publishSoon() {
        guard onPublish != nil, !publishPending else {
            return
        }

        publishPending = true
        DispatchQueue.main.async { [self] in
            publishPending = false

            let shown = Set(windows.keys.filter { world.isVisible($0) && hidden[$0] == nil })
            let floating = Set(windows.keys.filter { world.workspace(containing: $0)?.floating[$0] != nil })
            let frames = windows.mapValues(\.frame)
            let floatingFrames = focused.flatMap(world.workspace(containing:)).map { Array($0.floating.values) } ?? []
            let raised = Set(windows.keys.filter(levels.isRaised))

            onPublish?(TapView(
                takesFocus: shown,
                raised: raised,
                floating: floating,
                frames: frames,
                floatingFrames: floatingFrames,
                focused: focused,
                focusUnmanaged: focusInUnmanagedWindow,
                lastCursorMove: lastCursorMove
            ))
        }
    }

    func setFrame(_ id: WindowID, _ r: CGRect) {
        if let w = windows[id] { connections?.connection(w.pid)?.setFrame(id, r) }
    }

    func appName(of id: WindowID) -> String? { windows[id]?.app }

    /// A click or key press: focus that follows it is the user's doing.
    /// `click`: the user's own click focuses what it hits, so a focus command
    /// still waiting for its app is stale.
    func noteInput(at t: Date, click: Bool) {
        history.input(at: t)
        guard click else {
            return
        }

        focusMovedOn()
        zooming.removeAll()  // a double click that zoomed nothing is over
    }

    /// From what swwm already knows: no AX round-trips, so a hung app cannot
    /// stall a query (and the event tap on the main thread).
    func windowInfo(_ id: WindowID) -> WindowInfo? {
        windows[id].map {
            WindowInfo(app: $0.app, title: $0.title, frame: world.shownFrame(of: id) ?? .zero)
        }
    }

    func titleChanged(_ id: WindowID, _ title: String) {
        windows[id]?.title = title
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

    func setPosition(_ id: WindowID, _ p: CGPoint) {
        if let w = windows[id] { connections?.connection(w.pid)?.setPosition(id, p) }
    }

    /// Ends a modifier+left drag: a tiled window dropped on another tiled
    /// window swaps with it, or joins the active workspace of the display it
    /// was dropped on.
    func dropped(_ id: WindowID, at p: CGPoint) {
        guard let ws = world.workspace(containing: id), let from = world.monitor(of: ws.name) else {
            return
        }

        if ws.floating[id] != nil {
            readFrame(id) { f in if let f, ws.floating[id] != nil { ws.floating[id] = f } }
            return
        }

        touched.insert(ws.name)

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
        guard let ws = world.workspace(containing: id), let m = world.monitor(of: ws.name) else {
            return
        }

        if ws.floating[id] != nil {
            readFrame(id) { f in if let f, ws.floating[id] != nil { ws.floating[id] = f } }
            return
        }

        touched.insert(ws.name)
        ws.tree.resize(
            id,
            by: delta,
            in: world.workArea(of: m),
            gap: settings.gap
        )
        layout(m)
    }

    private func windowUnder(_ p: CGPoint, excluding id: WindowID) -> WindowID? {
        guard let ws = world.workspace(containing: id) else {
            return nil
        }

        return ws.tree.windows.first { $0 != id && world.shownFrame(of: $0)?.contains(p) == true }
    }
}

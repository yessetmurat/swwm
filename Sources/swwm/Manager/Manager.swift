//
//  Manager.swift
//  swwm
//
//  Created by Yesset Murat on 03.11.2026.
//

import AppKit
import SwwmCore

/// Applies the World to real windows and turns events and commands into
/// World changes. This file holds the state, the layout and the window
/// reads and writes; the extensions hold tracking, focus, commands, the
/// pointer, placement, levels, shadows and saving.
final class Manager: AppEvents {

    let world: World
    weak var connections: Connections?
    var onReload: () -> String? = { nil }               // error message when the config is not applied
    var onQuit: () -> Void = {}
    var onChange: () -> Void = {}                         // something the bar shows may have changed
    var onPublish: ((TapView) -> Void)?                   // hands the event tap what it decides from
    var publishPending = false

    // Windows
    var windows: [WindowID: ManagedWindow] = [:]
    var remembered = Remembered()                         // minimized windows and those of hidden apps
    var tilingKinds: Set<String> = []                     // kinds a window of which took a tile's size
    var touched: Set<String> = []                         // workspaces whose tiles changed since start
    var finderHasDesktop = true                           // Finder lists a desktop (`CreateDesktop` not off)

    // The last run
    var startPids: Set<pid_t> = []                        // apps running when swwm started
    var joinedPids: Set<pid_t> = []                       // of those, the ones that reported their windows
    var saved: SavedWorkspaces?                           // read at start
    var savePending = false
    var lastSaved: Data?                                  // what the file holds
    /// Per login session: the temporary directory is cleared on reboot.
    static let savedFile = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "swwm-workspaces.json")

    // The Dock module
    let dock = DockClient()
    var dockModuleInstalled = false                       // set at start from DockModuleInstaller.isInstalled
    var shadowNoticeShown = false
    var dockAwaited = false                               // asking until the Dock module answers
    var onShadowUnavailable: () -> Void = {}
    var levels = FloatingLevels()                         // windows swwm put at the floating level
    var levelNoticeShown = false
    var onLevelUnavailable: () -> Void = {}

    // Focus
    var history = FocusHistory()
    var echoes = FocusEchoes()                            // answers to focus commands swwm has since replaced
    var focused: WindowID? { history.current }
    var lastCursorMove = Date.distantPast { didSet { publishSoon() } }  // a warp or swwm's own click
    /// True while the user is in a window swwm does not manage (a system prompt
    /// such as SecurityAgent's, a sheet, a launcher panel): focus-follows-mouse
    /// must not pull focus away from it. Kept from the focus reports.
    var focusInUnmanagedWindow = false { didSet { publishSoon() } }
    let park = FocusPark()
    var pendingPark: (info: MonitorInfo, points: [CGPoint])?  // a park waiting for the hidden windows to leave
    var pendingFocus: [MonitorID: DispatchWorkItem] = [:]
    // Workaround: after a close macOS activates some other app, with no event
    // saying it is done; swwm puts focus back after it.
    static let refocusWait = 0.05

    init(world: World) {
        self.world = world
    }

    var settings: Settings { world.config.settings }

    /// Apps running at start that have not reported their windows yet.
    var pendingStart: Set<pid_t> { startPids.subtracting(joinedPids) }

    func appName(of id: WindowID) -> String? { windows[id]?.app }

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

    /// The set of managed windows changed: the window server sends moved and
    /// resized events for these, and the app connections report their focus
    /// by ID alone.
    func windowsChanged() {
        let ids = Array(windows.keys)
        WindowServer.watch(ids)
        connections?.setManaged(Set(ids))
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

            for id in other.windows {
                guard let w = windows[id], w.hidden != m || w.needsPlacement else {
                    continue
                }

                setPosition(id, hiddenOrigin(for: w.frame.size, on: info, others: others))
                windows[id]?.needsPlacement = false
                windows[id]?.leaving = true  // until its moved event, or the app turns the write down
                windows[id]?.hidden = m
            }
        }

        let area = world.workArea(of: m)
        for id in ws.windows { windows[id]?.leaving = false }  // shown again before their moved event came

        for (id, r) in ws.tree.frames(in: area, gap: settings.gap) where id != ws.zoomed {
            // Its size check found its workspace hidden: due now.
            if windows[id]?.checkWhenShown == true {
                windows[id]?.checkWhenShown = false
                checkLater(id)
            }

            putInPlace(id, r)
        }

        for (id, r) in ws.floating {
            let frame = shownFloatingFrame(r, on: info, area: area)
            guard let w = windows[id], w.hidden != nil || w.needsPlacement || frame != r else {
                continue
            }

            ws.floating[id] = frame
            setFrame(id, frame)
            windows[id]?.hidden = nil
            windows[id]?.needsPlacement = false
        }

        if let z = ws.zoomed, let w = windows[z] {
            putInPlace(z, area)
            connections?.connection(w.pid)?.raise(z)
        }
    }

    /// Gives a shown window its frame. No write when the window was read at
    /// that frame and nothing has touched it since: most layouts leave most
    /// tiles where they are. The window server's moved and resized events
    /// are what make swwm read again (`refreshFrame`).
    private func putInPlace(_ id: WindowID, _ r: CGRect) {
        guard let w = windows[id] else {
            return
        }

        let there = w.hidden == nil && !w.needsPlacement && w.settledAt.map { near($0, r) } == true
        if !there { setFrame(id, r) }

        windows[id]?.hidden = nil
        windows[id]?.needsPlacement = false
    }

    /// Puts every hidden window back on screen; called on quit.
    func restoreAll() {
        for id in Array(windows.keys) where windows[id]?.hidden != nil {
            // Nil when its display is gone already (quit during a display change).
            if let r = world.shownFrame(of: id) { setFrame(id, r) }
            windows[id]?.hidden = nil
        }

        connections?.flush()

        if settings.windowShadow != .on {
            dock.setShadowsSync(windows.keys.map { (id: $0, shadow: true) })
        }
        dock.setLevelsSync(levels.removeAll().map { (id: $0.window, level: $0.level) })
    }

    func displaysChanged() {
        world.updateMonitors(Displays.current())
        log.debug("displays \(self.world.monitors.map { "\($0.id) \($0.name)" }.joined(separator: ", "), privacy: .public)")

        // Positions refer to the old arrangement: layout places every hidden
        // window again.
        for id in Array(windows.keys) where windows[id]?.hidden != nil { windows[id]?.needsPlacement = true }
        layoutAll()

        // The focused window's workspace may have moved onto a display that shows another one.
        if let f = focused, !world.isVisible(f), let ws = world.workspace(containing: f),
           let m = world.monitor(of: ws.name) {
            focus(monitor: m)
        }
    }

    // MARK: - Window reads and writes

    func setFrame(_ id: WindowID, _ r: CGRect) {
        guard let w = windows[id] else {
            return
        }

        touch(id)
        connections?.connection(w.pid)?.setFrame(id, r)
    }

    func setPosition(_ id: WindowID, _ p: CGPoint) {
        guard let w = windows[id] else {
            return
        }

        touch(id)
        connections?.connection(w.pid)?.setPosition(id, p)
    }

    /// A write is sent or a frame asked for: what was read before is old.
    private func touch(_ id: WindowID) {
        windows[id]?.touches += 1
        windows[id]?.settledAt = nil
    }

    /// The window's frame as its app has it now, for decisions made after
    /// something moved it; `reply` runs on main.
    func readFrame(_ id: WindowID, reply: @escaping (CGRect?) -> Void) {
        guard let w = windows[id] else {
            return reply(nil)
        }

        // Before anything can fail: whoever asks has a reason to doubt the last frame read.
        touch(id)
        let asked = windows[id]?.touches

        guard let c = connections?.connection(w.pid) else {
            return reply(nil)
        }

        c.readFrame(id) { [weak self] f in
            if let self, let f {
                self.windows[id]?.frame = f

                // Nothing was written or asked since: this is where its app or the user has it.
                if asked == self.windows[id]?.touches {
                    self.windows[id]?.settledAt = f
                    self.learnFloatingFrame(id, f)
                }
                self.publishSoon()
            }
            reply(f)
        }
    }

    /// A floating window keeps the frame its app reports while it is shown on
    /// its own display. Not one hidden or on a workspace not shown (that is
    /// the hiding spot), and not one on another display (macOS moved it off
    /// a display that went away; its place there is kept for the return).
    private func learnFloatingFrame(_ id: WindowID, _ f: CGRect) {
        guard let w = windows[id],
              w.hidden == nil,
              world.isVisible(id),
              let ws = world.workspace(containing: id),
              ws.floating[id] != nil,
              let m = world.monitor(of: ws.name),
              let info = world.monitorInfo(m),
              shownFloatingFrame(f, on: info, area: world.workArea(of: m)) == f else {
            return
        }

        ws.floating[id] = f
    }

    /// The window server moved or resized a managed window: learn its frame;
    /// one still settling that its app resized gets its tile back.
    func refreshFrame(_ id: WindowID) {
        guard windows[id] != nil else {
            return
        }

        readFrame(id) { [weak self] _ in self?.windowResized(id) }
    }
}

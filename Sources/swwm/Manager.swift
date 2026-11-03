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
    let shadows = ShadowClient()
    var shadowModuleInstalled = false                      // set at start from ShadowInstaller.isInstalled
    private var shadowNoticeShown = false
    var onShadowUnavailable: () -> Void = {}
    private var remembered: [WindowID: String] = [:]     // workspace of minimized/hidden windows
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
        for app in NSWorkspace.shared.runningApplications where app.isManageable {
            adopt(app)
        }
        layoutAll()
        applyShadowAll()
        if let app = NSWorkspace.shared.frontmostApplication { appActivated(app) }
    }

    func adopt(_ app: NSRunningApplication) {
        for w in AXWindow.windows(of: app) {
            let f = w.frame
            track(w, near: CGPoint(x: f.midX, y: f.midY))
        }
    }

    /// Adds a window to the World: to its rule's workspace, else to the
    /// active workspace of the display at `point`. Dialogs, sheets and
    /// fullscreen windows are not managed.
    @discardableResult
    func track(_ w: AXWindow, near point: CGPoint) -> Bool {
        guard windows[w.id] == nil, NSRunningApplication(processIdentifier: w.pid)?.isManageable == true,
              w.isStandard, w.level == 0, !w.isFullScreen, !w.isMinimized else {
            log.debug("skip \(w.id, privacy: .public) \(w.appName, privacy: .public) role=\(w.element.attribute(kAXRoleAttribute) as String? ?? "-", privacy: .public) sub=\(w.element.attribute(kAXSubroleAttribute) as String? ?? "-", privacy: .public) level=\(w.level, privacy: .public) full=\(w.isFullScreen, privacy: .public) min=\(w.isMinimized, privacy: .public)")
            return false
        }
        let rule = world.config.rules.first { $0.matches(app: w.appName, title: w.title) }
        let floats = rule?.float == true || !w.isResizable
        let frame = w.frame
        let target = remembered.removeValue(forKey: w.id)
            ?? rule?.workspace
            ?? world.monitor(at: point).flatMap(world.activeWorkspace(on:))
        guard let target else { return false }
        windows[w.id] = w
        titles[w.id] = w.title
        world.add(w.id, to: target, floatingFrame: floats ? frame : nil)
        applyShadow(w.id)
        return true
    }

    /// Sets a window's shadow to what `window-shadow` wants, if anything.
    func applyShadow(_ id: WindowID) {
        let floating = world.workspace(containing: id)?.floating[id] != nil
        guard let want = shadowWanted(floating: floating, mode: settings.windowShadow) else { return }
        shadows.set(id, shadow: want) { [weak self] ok in
            guard let self, !ok, self.shadowModuleInstalled, !self.shadowNoticeShown else { return }
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
        if remember, let ws = world.workspace(containing: id), let wm = world.monitor(of: ws.name) {
            remembered[id] = ws.name
            // A hidden app's window parked off-screen must come back on screen
            // when the app unhides, even if swwm is gone by then.
            if hidden[id] != nil {
                let area = world.workArea(of: wm)
                w.setFrame(ws.floating[id].map { shownFloatingFrame($0, on: world.monitorInfo(wm)!, area: area) }
                    ?? ws.tree.frames(in: area, gap: settings.gap)[id] ?? area)
            }
        }
        let now = Date()
        let hadFocus = history.wasRecentlyFocused(id, now: now)
        history.removed(at: now)
        let m = world.remove(id)
        windows[id] = nil
        titles[id] = nil
        hidden[id] = nil
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
        defer { onChange() }
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
            shadows.setSync(windows.keys.map { (id: $0, shadow: true) })
        }
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
        if warp, settings.mouseFollowsFocus, !w.frame.contains(Displays.cursor) {
            let f = w.frame
            lastWarp = Date()
            CGWarpMouseCursorPosition(CGPoint(x: f.midX, y: f.midY))
        }
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
        guard track(w, near: Displays.cursor), let ws = world.workspace(containing: w.id), let m = world.monitor(of: ws.name) else { return }
        layout(m)
    }

    func windowGone(_ id: WindowID) { untrack(id, remember: false) }

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
            guard (info[kCGWindowLayer as String] as? Int) == 0 else { continue }
            // Hidden windows keep a sliver on screen; they must never take focus.
            let id = (info[kCGWindowNumber as String] as? Int).map(WindowID.init)
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

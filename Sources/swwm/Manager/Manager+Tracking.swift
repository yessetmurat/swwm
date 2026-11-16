//
//  Manager+Tracking.swift
//  swwm
//
//  Created by Yesset Murat on 16.11.2026.
//

import AppKit
import SwwmCore

/// Which windows swwm manages: taken in as their apps report them, let go
/// when they close, minimize, hide or their app quits.
extension Manager {

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
            log.debug("manage \(s.id, privacy: .public) \(s.app, privacy: .public) ws=\(target, privacy: .public) floating=\(floating, privacy: .public) adopting=\(adopting, privacy: .public)")
            levels.adopt(s.id, pid: s.pid)

            var new = ManagedWindow(s)
            new.opened = s.frame
            windows[s.id] = new
            windowsChanged()

            world.add(s.id, to: target, floatingFrame: floating ? s.frame : nil)
            if !adopting { touched.insert(target) }
            applyShadow(s.id)
            applyLevel(s.id)
            return true
        }
    }

    /// Native tabs are windows of their own and only the shown one is listed:
    /// a tile follows the shown tab of its group, hidden or zooming as it was.
    private func takeOver(_ old: WindowID, by w: AppWindow) {
        log.debug("tab \(w.id, privacy: .public) takes over \(old, privacy: .public)")

        world.replace(old, with: w.id)

        var new = ManagedWindow(w)
        new.hidden = windows[old]?.hidden
        new.zooming = windows[old]?.zooming
        windows[old] = nil
        windows[w.id] = new
        windowsChanged()

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
        // An app's list is not swwm's to trust: one ID twice must not be fatal.
        let frames = Dictionary(candidates.map { ($0.id, $0.frame) }, uniquingKeysWith: { first, _ in first })
        let next = tabSibling(of: r, among: frames)
        return candidates.first { $0.id == next }
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
            if w.hidden != nil, let r = world.shownFrame(of: id) { setFrame(id, r) }
        }

        // Minimized or hidden it lives on: back to the normal level, so it is
        // managed again when it returns.
        send(remember ? levels.set(id, pid: w.pid, floating: false) : levels.gone(id))

        let now = Date()
        let hadFocus = history.wasRecentlyFocused(id, now: now)
        history.removed(at: now)

        let m = world.remove(id)
        windows[id] = nil
        windowsChanged()

        guard let m else {
            return
        }

        layout(m)
        if hadFocus {
            history.focused(nil, at: now)
            refocus(m)
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
    func appWindows(_ found: [AppWindow], pid: pid_t, adopting: Bool, listsDesktop: Bool) {
        if NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.apple.finder" {
            finderHasDesktop = listsDesktop
        }

        guard adopting else {
            if found.map(windowCreated).contains(true) { readFocusIfFrontmost(pid) }
            return
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

        let adopted = found.map(\.id).filter { windows[$0] != nil }.map { (id: $0, asked: world.shownFrame(of: $0)?.size) }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.startRefusalCheck) { [weak self] in
            for a in adopted { self?.floatIfRefused(a.id, asked: a.asked) }
        }

        readFocusIfFrontmost(pid)
    }

    func windowAppeared(_ w: AppWindow) {
        if windowCreated(w) { readFocusIfFrontmost(w.pid) }
    }

    /// A window's focus report may come before the window is manageable (still
    /// minimized, its app still hidden, no subrole yet): once it is managed,
    /// its app is asked again, or focus would stay unknown until the next change.
    private func readFocusIfFrontmost(_ pid: pid_t) {
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid { connections?.connection(pid)?.readFocus() }
    }

    func titleChanged(_ id: WindowID, _ title: String) {
        windows[id]?.title = title
    }

    /// An app that left writes unanswered (stopped, or busy for long)
    /// answers again: its windows go where their workspaces want them.
    func appAnswered(_ ids: Set<WindowID>) {
        let mine = ids.filter { windows[$0] != nil }
        for id in mine { windows[id]?.needsPlacement = true }

        Set(mine.compactMap { world.workspace(containing: $0).flatMap { world.monitor(of: $0.name) } }).forEach(layout)
    }
}

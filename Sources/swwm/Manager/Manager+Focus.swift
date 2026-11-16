//
//  Manager+Focus.swift
//  swwm
//
//  Created by Yesset Murat on 16.11.2026.
//

import AppKit
import SwwmCore

/// Keyboard focus: where swwm sends it, what the apps report, and the park
/// that holds it on a display with no windows.
extension Manager {

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

        pendingPark = nil
        park.clear()
        if let c = connections { c.connection(w.pid)?.focus(id, ticket: c.focusTicket.next()) }

        echoes.commanded(id, from: focused)
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
            let from = focused
            history.focused(nil, at: Date())
            cancelPendingFocus()
            echoes.commanded(nil, from: from)

            // The user's key or click that led here is used up: focus moves
            // that follow swwm's own desktop click are not the user's.
            history.input(at: .distantPast)

            let area = world.workArea(of: m)
            let points = parkPoints(cursor: Displays.cursor, area: area, mouseFollowsFocus: settings.mouseFollowsFocus)
            if settings.mouseFollowsFocus, !info.frame.contains(Displays.cursor), let p = points.last {
                lastCursorMove = Date()
                CGWarpMouseCursorPosition(p)
            }

            pendingPark = (info, points)
            evaluatePark()
        }
    }

    /// The windows of the workspace just hidden may still be on screen: click
    /// Finder's desktop once the window server has moved the ones in the way
    /// (their moved events call this again); park without a click when
    /// something else covers every point. Focus going elsewhere meanwhile
    /// drops the pending park.
    private func evaluatePark() {
        guard let pending = pendingPark else {
            return
        }

        let onScreen = WindowServer.onScreen()
        let desktop = Int(CGWindowLevelForKey(.desktopIconWindow))
        let leaving = Set(windows.values.filter(\.leaving).map(\.id))

        for p in pending.points {
            switch parkStep(
                at: p,
                onScreen: onScreen,
                leaving: leaving,
                desktopLayer: desktop
            ) {
            case .click:
                pendingPark = nil
                echoes.movedOn()         // the park is done: what is reported from now on is news
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
        echoes.movedOn()                // the park is done: what is reported from now on is news
        focusInUnmanagedWindow = false  // swwm holds focus itself
        park.park(on: pending.info, desktopPoint: nil)
    }

    /// The window server has a window where swwm or its app put it.
    func windowMoved(_ id: WindowID) {
        guard windows[id]?.leaving == true else {
            return
        }

        windows[id]?.leaving = false
        evaluatePark()
    }

    /// The app did not take a write: the window stays where it was, so a
    /// park waiting for it to leave must not wait any longer.
    func writeFailed(_ id: WindowID) { windowMoved(id) }

    /// After a close, macOS activates some other app, maybe on another
    /// display. Wait for that, then put focus back on display `m`.
    func refocus(_ m: MonitorID) {
        log.debug("refocus display \(m, privacy: .public)")
        pendingFocus[m]?.cancel()

        let item = DispatchWorkItem { [weak self] in
            self?.pendingFocus[m] = nil
            self?.focus(monitor: m)
        }

        pendingFocus[m] = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.refocusWait, execute: item)
    }

    // MARK: - Reports

    func focusChanged(_ report: FocusReport, pid: pid_t) {
        switch report {
        case .managed(let id):
            windowFocusChanged(id, pid: pid, read: nil)
        case .window(let w):
            windowFocusChanged(w.id, pid: pid, read: w)
        case .none:
            // A background app closing its last window says nothing about focus.
            if focusReportIsFocus(from: pid, frontmost: NSWorkspace.shared.frontmostApplication?.processIdentifier) { noFocusedWindow() }
        }
    }

    /// A focus change reported by an app. A window that was not manageable
    /// when it appeared (fullscreen, subrole not ready yet) gets another try
    /// from `w`, its report as just read.
    private func windowFocusChanged(_ id: WindowID, pid: pid_t, read w: AppWindow?) {
        // An app still starting reports its windows first, with their last places.
        if windows[id] == nil, let w, !pendingStart.contains(pid) { windowCreated(w) }

        guard focusReportIsFocus(from: pid, frontmost: NSWorkspace.shared.frontmostApplication?.processIdentifier) else {
            return
        }

        // An answer to a focus command swwm has since replaced says nothing
        // new: it must not take focus back, nor cancel the newer command.
        let managed = windows[id] != nil
        if managed, echoes.reported(id) == .echo { return }

        focusInUnmanagedWindow = !managed
        if focusInUnmanagedWindow { focusMovedOn() }

        // Focus moved to a window swwm does not manage on another display:
        // the parked display no longer has the keyboard.
        if !managed, let m = park.monitor, let b = WindowServer.window(id)?.bounds,
           world.monitor(at: CGPoint(x: b.midX, y: b.midY)) != m {
            park.clear()
        }

        windowFocused(id)
    }

    /// Records focus changes made outside swwm (clicks, app switches).
    private func windowFocused(_ id: WindowID) {
        defer { onChange() }
        log.debug("windowFocused \(id, privacy: .public) managed=\(self.windows[id] != nil, privacy: .public)")
        guard windows[id] != nil, focused != id else {
            return
        }

        focusMovedOn()

        let now = Date()
        history.focused(id, at: now)
        pendingPark = nil  // a pending desktop click must not take focus back
        park.clear()
        world.noteFocused(id)

        // Mouse follows focus whoever moved it (a new window, cmd-tab, a Dock
        // click); after a hover or a click the cursor is on the window already.
        // The tile, not the window's frame: a new window may not be there yet.
        // Not around a close: the pending refocus moves the cursor itself.
        if settings.mouseFollowsFocus,
           pendingFocus.isEmpty,
           world.isVisible(id),
           let r = world.shownFrame(of: id),
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
    private func noFocusedWindow() {
        focusMovedOn()
        focusInUnmanagedWindow = false
    }

    /// An app swwm does not manage is frontmost now (a system prompt such as
    /// SecurityAgent's): the user is in its window.
    func unmanagedAppActivated() {
        focusMovedOn()
        focusInUnmanagedWindow = true
    }

    /// Focus moved somewhere swwm did not send it: a focus command still
    /// waiting for its app is stale, and every focus report counts again.
    private func focusMovedOn() {
        cancelPendingFocus()
        echoes.movedOn()
    }

    /// A focus command still waiting for its app is stale.
    private func cancelPendingFocus() { _ = connections?.focusTicket.next() }

    // MARK: - Input

    /// Focus asked for from the pointer (a hover or a modifier press), checked
    /// against the current state: the tap decided from a copy.
    func pointerFocus(_ id: WindowID, hover: Bool) {
        let isShown = windows[id].map { $0.hidden == nil } == true && world.isVisible(id)
        let shown: Set<WindowID> = isShown ? [id] : []

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
            guard isShown else {
                return
            }
        }

        focus(id, warp: false)
    }

    /// A click or key press: focus that follows it is the user's doing.
    /// `click`: the user's own click focuses what it hits (`id` when that is a
    /// managed window), so a focus command still waiting for its app is stale,
    /// and so are the answers to the commands before the click.
    func noteInput(at t: Date, click: Bool, on id: WindowID? = nil) {
        history.input(at: t)
        guard click else {
            // A key that reached an app may move focus anywhere (an app
            // switch, a window cycle): every report counts again.
            echoes.movedOn()
            return
        }

        cancelPendingFocus()
        if let id, windows[id] != nil { echoes.commanded(id, from: focused) } else { echoes.movedOn() }

        // A double click that zoomed nothing is over.
        for id in Array(windows.keys) where windows[id]?.zooming != nil { windows[id]?.zooming = nil }
    }
}

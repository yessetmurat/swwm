//
//  Manager+Placement.swift
//  swwm
//
//  Created by Yesset Murat on 04.11.2026.
//

import AppKit
import SwwmCore

/// Where a new window goes: its tile, or floating where it opened when it
/// cannot take a tile's size.
extension Manager {

    // Workaround: no event says that an app takes size changes for a new
    // window yet (an opening animation, Ghostty setting up), nor that a
    // fixed-size window never will; these waits are the asking again.
    static let sizeProbeWaits = [0.03, 0.06, 0.1, 0.15]
    static let refusalCheck = 0.3       // after settle: still not its tile's size
    static let startRefusalCheck = 0.5  // after the first layout at start

    func windowCreated(_ r: Reported) {
        let id = r.window.id
        // New windows open on the display under the cursor.
        let returning = remembered.contains(id)  // unminimized or unhidden: keeps its place
        guard track(r, adopting: false), let w = windows[id], let ws = world.workspace(containing: id),
              let m = world.monitor(of: ws.name) else { return }
        if !returning, ws.tree.contains(id), world.isVisible(id) {
            switch tilesByKind[w.kind] {
            case true?: settle(id, on: m)
            case false?:
                opened[id] = nil
                makeFloating(id, frame: w.frame)
            case nil: place(id, attempt: 0)
            }
        } else {
            settle(id, on: m)
        }
    }

    /// Tiles a new window or floats it, without first showing it in a tile it
    /// cannot fill: a window that stretches one way only floats where it opened.
    /// One that takes no size change yet stays where the app put it and is
    /// asked again; after that it tiles, and the size check floats it if it
    /// still refuses.
    private func place(_ id: WindowID, attempt: Int) {
        guard let w = windows[id], let ws = world.workspace(containing: id), ws.tree.contains(id),
              let m = world.monitor(of: ws.name), world.isVisible(id) else {
            opened[id] = nil  // floated, moved or gone meanwhile: no size check follows
            return
        }
        let axes = w.ax.resizableAxes()
        let waits = Self.sizeProbeWaits
        if axes.width != axes.height {
            tilesByKind[w.kind] = false
            opened[id] = nil
            makeFloating(id, frame: w.frame)
        } else if !axes.width, attempt < waits.count {
            let wait = waits[attempt] - (attempt > 0 ? waits[attempt - 1] : 0)
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in self?.place(id, attempt: attempt + 1) }
        } else {
            if axes.width { tilesByKind[w.kind] = true }
            settle(id, on: m)
        }
    }

    /// Puts a window in its place before the rest of the display. Until the
    /// size check, a size the app sets itself is put back (`windowResized`).
    private func settle(_ id: WindowID, on m: MonitorID) {
        if world.isVisible(id), let r = world.shownFrame(of: id) { windows[id]?.ax.setFrame(r) }
        settling.insert(id)
        layout(m)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.refusalCheck) { [weak self] in self?.floatIfRefused(id) }
    }

    /// A settling window whose app gave it another size (its frame just
    /// reported) gets its tile again. Not while the user drags.
    func windowResized(_ id: WindowID) {
        guard settling.contains(id), !CGEventSource.buttonState(.combinedSessionState, button: .left),
              world.isVisible(id), let w = windows[id], let r = world.shownFrame(of: id), !near(w.frame, r) else { return }
        w.ax.setFrame(r)
    }

    /// A tiled window that does not take its tile's size (a fixed-size dialog)
    /// would overlap its neighbors: it floats instead. 20pt of slack for
    /// windows that size in steps. Only this window: the next one of its kind
    /// may fit its tile.
    func floatIfRefused(_ id: WindowID) {
        settling.remove(id)
        let start = opened.removeValue(forKey: id)
        guard let w = windows[id], world.isVisible(id), let ws = world.workspace(containing: id), ws.zoomed != id,
              ws.tree.contains(id), let r = world.shownFrame(of: id) else { return }
        let now = w.frame
        guard !near(CGRect(origin: .zero, size: now.size), CGRect(origin: .zero, size: r.size), tolerance: 20) else { return }
        makeFloating(id, frame: start ?? now)
    }

    /// Floats a tiled window at `frame`: where the app opened it, as a tile
    /// may have stretched it the one way it can. Off the work area: centered.
    private func makeFloating(_ id: WindowID, frame f: CGRect) {
        guard let w = windows[id], let ws = world.workspace(containing: id), let m = world.monitor(of: ws.name),
              let info = world.monitorInfo(m) else { return }
        log.debug("float \(id, privacy: .public) \(w.app, privacy: .public)")
        let frame = shownFloatingFrame(f, on: info, area: world.workArea(of: m))
        world.remove(id)
        world.add(id, to: ws.name, floatingFrame: frame)
        if w.frame != frame { w.ax.setFrame(frame) }
        layout(m)
        applyShadow(id)
        applyLevel(id)
    }
}

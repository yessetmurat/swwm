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

    func windowCreated(_ new: AppWindow) {
        let id = new.id

        // New windows open on the display under the cursor.
        let returning = remembered.contains(id)  // unminimized or unhidden: keeps its place

        guard track(new, adopting: false),
              let w = windows[id],
              let ws = world.workspace(containing: id),
              let m = world.monitor(of: ws.name) else {
            return
        }

        if !returning, ws.tree.contains(id), world.isVisible(id) {
            switch tilesByKind[w.kind] {
            case true?: settle(id, on: m)
            case false?:
                opened[id] = nil
                makeFloating(id, frame: w.frame, because: "its kind floats")
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
        guard let w = windows[id], let c = connections?.connection(w.pid) else {
            return
        }

        c.probeAxes(id) { [weak self] width, height in self?.placed(
            id,
            attempt: attempt,
            width: width,
            height: height
        ) }
    }

    private func placed(
        _ id: WindowID,
        attempt: Int,
        width: Bool,
        height: Bool
    ) {
        guard let w = windows[id],
              let ws = world.workspace(containing: id),
              ws.tree.contains(id),
              let m = world.monitor(of: ws.name),
              world.isVisible(id) else {
            opened[id] = nil  // floated, moved or gone meanwhile: no size check follows
            return
        }

        switch probeStep(
            width: width,
            height: height,
            attempt: attempt,
            waits: Self.sizeProbeWaits
        ) {
        case .float:
            tilesByKind[w.kind] = false
            opened[id] = nil
            makeFloating(id, frame: w.frame, because: "it stretches one way only")
        case .askAgain(let wait):
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in self?.place(id, attempt: attempt + 1) }
        case .tile(let learned):
            if let learned { tilesByKind[w.kind] = learned }
            settle(id, on: m)
        }
    }

    /// Puts a window in its place before the rest of the display. Until the
    /// size check, a size the app sets itself is put back (`windowResized`).
    private func settle(_ id: WindowID, on m: MonitorID) {
        if world.isVisible(id), let r = world.shownFrame(of: id) { setFrame(id, r) }

        settling.insert(id)
        layout(m)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.refusalCheck) { [weak self] in self?.floatIfRefused(id) }
    }

    /// A settling window whose app gave it another size (its frame just
    /// reported) gets its tile again. Not while the user drags.
    func windowResized(_ id: WindowID) {
        guard settling.contains(id),
              !CGEventSource.buttonState(.combinedSessionState, button: .left),
              world.isVisible(id),
              let w = windows[id],
              let r = world.shownFrame(of: id),
              !near(w.frame, r) else {
            return
        }
        setFrame(id, r)
    }

    /// A tiled window that does not take its tile's size (a fixed-size dialog)
    /// would overlap its neighbors: it floats instead. 20pt of slack for
    /// windows that size in steps. Only this window: the next one of its kind
    /// may fit its tile.
    func floatIfRefused(_ id: WindowID) {
        settling.remove(id)
        let start = opened.removeValue(forKey: id)

        readFrame(id) { [weak self] now in
            guard let self,
                  let now,
                  self.world.isVisible(id),
                  let ws = self.world.workspace(containing: id),
                  ws.zoomed != id,
                  ws.tree.contains(id),
                  let r = self.world.shownFrame(of: id),
                  !near(CGRect(origin: .zero, size: now.size), CGRect(origin: .zero, size: r.size), tolerance: 20) else {
                return
            }

            self.makeFloating(id, frame: start ?? now, because: "it kept \(now.size), not its tile's \(r.size)")
        }
    }

    /// Floats a tiled window at `frame`: where the app opened it, as a tile
    /// may have stretched it the one way it can. Off the work area: centered.
    private func makeFloating(_ id: WindowID, frame f: CGRect, because reason: String) {
        guard let w = windows[id],
              let ws = world.workspace(containing: id),
              let m = world.monitor(of: ws.name),
              let info = world.monitorInfo(m) else {
            return
        }

        // Kept in the system log: an automatic float is rare and puzzling afterwards.
        log.notice("float \(id, privacy: .public) \(w.app, privacy: .public): \(reason, privacy: .public)")
        let frame = shownFloatingFrame(f, on: info, area: world.workArea(of: m))

        world.remove(id)
        world.add(id, to: ws.name, floatingFrame: frame)
        setFrame(id, frame)
        layout(m)
        applyShadow(id)
        applyLevel(id)
    }
}

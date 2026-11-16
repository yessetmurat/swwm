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

    // Workaround: a window can cut size changes short for a while after it
    // opens (Windows App's session window: 0.25 s to over 0.4 s), and no event
    // says when that ends; these waits are the asking again.
    static let shortTileWaits = [0.2, 0.3, 0.5, 1.0]

    /// True when the window is managed from now on.
    @discardableResult
    func windowCreated(_ new: AppWindow) -> Bool {
        let id = new.id

        // New windows open on the display under the cursor.
        let returning = remembered.contains(id)  // unminimized or unhidden: keeps its place

        guard track(new, adopting: false) else {
            return false
        }

        guard let w = windows[id],
              let ws = world.workspace(containing: id),
              let m = world.monitor(of: ws.name) else {
            return true
        }

        if !returning, ws.tree.contains(id), world.isVisible(id), !tilingKinds.contains(w.kind) {
            place(id, attempt: 0)
        } else {
            settle(id, on: m)
        }

        return true
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

        c.probeAxes(id) { [weak self] width, height in
            self?.placed(
                id,
                attempt: attempt,
                width: width,
                height: height
            )
        }
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
            windows[id]?.opened = nil  // floated, moved or gone meanwhile: no size check follows
            return
        }

        switch probeStep(
            width: width,
            height: height,
            attempt: attempt,
            waits: Self.sizeProbeWaits
        ) {
        case .float:
            // Only this window: a probe of a window still setting itself up
            // may be off, and its whole kind would float for good.
            windows[id]?.opened = nil
            makeFloating(id, frame: w.frame, because: "it stretches one way only")
        case .askAgain(let wait):
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in self?.place(id, attempt: attempt + 1) }
        case .tile(let learned):
            if learned == true { tilingKinds.insert(w.kind) }
            settle(id, on: m)
        }
    }

    /// Puts a window in its place before the rest of the display. Until the
    /// size check, a size the app sets itself is put back (`windowResized`).
    private func settle(_ id: WindowID, on m: MonitorID) {
        if world.isVisible(id), let r = world.shownFrame(of: id) { setFrame(id, r) }

        windows[id]?.settling = true
        layout(m)
        checkLater(id)
    }

    /// Asks after `refusalCheck` whether the window took its tile, as that
    /// tile is now.
    func checkLater(_ id: WindowID) {
        let asked = world.shownFrame(of: id)?.size
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.refusalCheck) { [weak self] in self?.floatIfRefused(id, asked: asked) }
    }

    /// A tile the user double-clicked by its title bar: macOS zooms it, and
    /// each resize that follows puts it back in its tile (`windowResized`).
    func titleDoubleClicked(_ id: WindowID) {
        guard let ws = world.workspace(containing: id), ws.tree.contains(id) else {
            return
        }

        windows[id]?.zooming = false
    }

    /// A settling window whose app gave it another size (its frame just
    /// reported) gets its tile again, not while the user drags. So does a
    /// zooming one that changed size (a title-bar drag only moves it), until
    /// it is back in its tile; a frame read before the zoom does not count.
    func windowResized(_ id: WindowID) {
        guard world.isVisible(id), let w = windows[id], let r = world.shownFrame(of: id) else {
            return
        }

        if let putBack = w.zooming {
            let resized = !near(CGRect(origin: .zero, size: w.frame.size), CGRect(origin: .zero, size: r.size))
            if resized {
                windows[id]?.zooming = true
                setFrame(id, r)
            } else if putBack, near(w.frame, r) {
                windows[id]?.zooming = nil
            }
            return
        }

        guard w.settling,
              !CGEventSource.buttonState(.combinedSessionState, button: .left),
              !near(w.frame, r) else {
            return
        }
        setFrame(id, r)
    }

    /// A tiled window larger than its tile (a fixed-size dialog) would overlap
    /// its neighbors: it floats instead. One smaller covers nothing: it stays
    /// and is asked again, not while the user drags, and keeps the size it
    /// ends up with. Only this window: the next one of its kind may fit its tile.
    /// `asked`: the tile's size when this check was asked for. A tile that
    /// changed since (a neighbor came or went) restarts the wait: the window
    /// has not had its time to take the new size. A window whose workspace
    /// is not shown is checked once it is (`layout`).
    func floatIfRefused(_ id: WindowID, attempt: Int = 0, asked: CGSize? = nil) {
        readFrame(id) { [weak self] now in
            guard let self else {
                return
            }

            let ws = self.world.workspace(containing: id)
            let tiled = ws?.tree.contains(id) == true && ws?.zoomed != id && self.windows[id]?.zooming == nil
            let tile = self.world.isVisible(id) ? self.world.shownFrame(of: id) : nil

            switch refusalStep(
                tiled: tiled,
                tile: tile?.size,
                asked: asked,
                window: now?.size,
                attempt: attempt,
                waits: Self.shortTileWaits
            ) {
            case .settled:
                self.settled(id)
            case .whenShown:
                self.windows[id]?.settling = true
                self.windows[id]?.checkWhenShown = true
            case .waitAgain:
                self.checkLater(id)
            case .tileAgain(let wait):
                guard let tile else {
                    return
                }

                if !CGEventSource.buttonState(.combinedSessionState, button: .left) { self.setFrame(id, tile) }
                DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
                    self?.floatIfRefused(id, attempt: attempt + 1, asked: tile.size)
                }
            case .float:
                guard let now, let tile else {
                    return
                }

                let start = self.settled(id)
                self.makeFloating(id, frame: start ?? now, because: "it kept \(now.size), not its tile's \(tile.size)")
            }
        }
    }

    /// The size check is over; returns where the app opened the window.
    @discardableResult
    private func settled(_ id: WindowID) -> CGRect? {
        let start = windows[id]?.opened

        windows[id]?.opened = nil
        windows[id]?.settling = false
        windows[id]?.checkWhenShown = false

        return start
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

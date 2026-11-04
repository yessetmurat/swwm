//
//  Manager+Levels.swift
//  swwm
//
//  Created by Yesset Murat on 04.11.2026.
//

import AppKit
import SwwmCore

/// Floating windows stay above tiled ones: through the Dock module they get
/// the floating window level, and the normal level once they tile. Their
/// app's sheets and dialogs go up with them as soon as the window server
/// has them on screen, well before the app reports them (System Settings:
/// about 250 ms later).
extension Manager {

    func applyLevel(_ id: WindowID) {
        guard let pid = windows[id]?.pid else { return }
        let floating = world.workspace(containing: id)?.floating[id] != nil
        let changes = levels.set(id, pid: pid, floating: floating)
        send(changes)
        // A sheet already open goes up with it.
        guard floating, !changes.isEmpty else { return }
        for w in WindowServer.onScreen(excludingDesktop: true) where w.pid == pid {
            send(levels.appeared(w.id, pid: w.pid, layer: w.layer, managed: windows[w.id] != nil))
        }
    }

    func applyLevelAll() {
        for id in windows.keys { applyLevel(id) }
    }

    func serverEvent(_ e: WindowServerEvent) {
        switch e {
        case .added(let id):
            guard let w = WindowServer.window(id) else { return }
            send(levels.appeared(id, pid: w.pid, layer: w.layer, managed: windows[id] != nil))
        case .removed(let id):
            send(levels.gone(id))
        case .moved, .resized:
            break
        }
    }

    func send(_ changes: [LevelChange]) {
        for c in changes {
            log.debug("level \(c.window, privacy: .public) -> \(c.level, privacy: .public)")
            dock.setLevel(c.window, c.level) { [weak self] reply in
                guard let self, reply != .done else { return }
                self.levels.failed(c)  // asked again on the next change or Dock restart
                // Unreachable is the shadow notice's case; turned down means an older payload.
                guard reply == .rejected, self.dockModuleInstalled, !self.levelNoticeShown else { return }
                self.levelNoticeShown = true
                self.onLevelUnavailable()
            }
        }
    }
}

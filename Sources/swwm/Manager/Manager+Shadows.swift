//
//  Manager+Shadows.swift
//  swwm
//
//  Created by Yesset Murat on 16.11.2026.
//

import AppKit
import SwwmCore

/// Window shadows, set through the Dock module as `window-shadow` says.
extension Manager {

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
}

//
//  Manager+Saving.swift
//  swwm
//
//  Created by Yesset Murat on 16.11.2026.
//

import AppKit
import SwwmCore

/// The state a restarted swwm picks up: each window's workspace, the tile
/// layouts and the shown workspaces.
extension Manager {

    /// Writes where each window is, once per run-loop turn of changes.
    func saveSoon() {
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
}

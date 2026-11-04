//
//  TapState.swift
//  swwm
//
//  Created by Yesset Murat on 04.11.2026.
//

import CoreGraphics
import Foundation
import os
import SwwmCore

/// What the event tap decides from, so it never waits on the main thread:
/// the config, and the manager's picture of the windows, published after
/// each change.
struct TapState: Sendable {

    var bindings: [KeyCombo: Command] = [:]
    var settings = Settings()
    var view = TapView()

    /// The managed window a click or hover at `p` reaches, as the window
    /// server hit-tests it. Any thread.
    func window(at p: CGPoint) -> WindowID? {
        guard let hit = WindowServer.windowAt(p).flatMap(WindowServer.window),
              let id = windowUnder(p, in: [hit], ownPID: getpid(), raised: view.raised.contains) else { return nil }
        // Hidden windows keep a sliver on screen; they must never take focus.
        return view.takesFocus.contains(id) ? id : nil
    }
}

/// The tap's copy of `TapState`, behind a lock. Any thread.
final class TapStateBox: Sendable {

    private let state = OSAllocatedUnfairLock(initialState: TapState())

    func read() -> TapState { state.withLock { $0 } }

    func update(_ change: @Sendable (inout TapState) -> Void) { state.withLock { change(&$0) } }
}

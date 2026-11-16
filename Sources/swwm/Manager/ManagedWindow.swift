//
//  ManagedWindow.swift
//  swwm
//
//  Created by Yesset Murat on 03.11.2026.
//

import AppKit
import SwwmCore

/// A window swwm manages, as its app last reported it, and everything swwm
/// keeps about it: it all goes when the window does.
struct ManagedWindow {

    let id: WindowID
    let pid: pid_t
    let app: String
    let kind: String          // windows of one kind tile or float alike
    var title: String
    var frame: CGRect

    var hidden: MonitorID?    // the display it is hidden on
    var needsPlacement = false  // the next layout moves it even where it looks placed
    var leaving = false       // hidden by swwm, until the window server has moved it
    var touches = 0           // writes sent and frames asked for: a frame read counts only when nothing followed
    var settledAt: CGRect?    // its frame as last read, while nothing has touched it since
    var opened: CGRect?       // where the app opened it, until the size check
    var settling = false      // new, until the size check: its own resizes are undone
    var checkWhenShown = false  // its size check found its workspace hidden
    var zooming: Bool?        // a tile double-clicked by its title bar; true once swwm put it back

    init(_ w: AppWindow) {
        id = w.id
        pid = w.pid
        app = w.app
        // The full-screen button tells an app's main windows from its panels
        // (Finder's browser windows from its Info windows).
        kind = "\(w.app)|\(w.hasFullScreenButton)"
        title = w.title
        frame = w.frame
    }
}

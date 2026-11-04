//
//  ManagedWindow.swift
//  swwm
//
//  Created by Yesset Murat on 03.11.2026.
//

import AppKit
import SwwmCore

/// A window swwm manages, as its app last reported it.
struct ManagedWindow {

    let id: WindowID
    let pid: pid_t
    let app: String
    let kind: String          // windows of one kind tile or float alike
    var title: String
    var frame: CGRect
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

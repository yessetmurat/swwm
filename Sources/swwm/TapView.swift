//
//  TapView.swift
//  swwm
//
//  Created by Yesset Murat on 03.11.2026.
//

import AppKit
import SwwmCore

/// What the manager tells the event tap about the windows, after each change.
struct TapView: Sendable {

    var takesFocus: Set<WindowID> = []   // managed and on screen
    var raised: Set<WindowID> = []       // at the floating level
    var floating: Set<WindowID> = []
    var frames: [WindowID: CGRect] = [:] // as their apps last reported them
    var floatingFrames: [CGRect] = []    // of the focused window's workspace
    var focused: WindowID?
    var focusUnmanaged = false
    var lastCursorMove = Date.distantPast
}

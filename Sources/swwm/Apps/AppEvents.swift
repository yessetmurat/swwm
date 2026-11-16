//
//  AppEvents.swift
//  swwm
//
//  Created by Yesset Murat on 04.11.2026.
//

import AppKit
import ApplicationServices
import SwwmCore

/// A write to a window: the newest one per window wins (a drag sends many).
enum WindowWrite: Sendable {

    case frame(CGRect)
    case position(CGPoint)
}

/// What an app reports as its focused window.
enum FocusReport: Sendable {

    case managed(WindowID)  // a window swwm manages: its ID says it all, nothing else is read
    case window(AppWindow)  // any other window, as just read
    case none               // the app has no focused window
}

/// What app connections tell the manager, on the main thread, in each app's
/// order.
protocol AppEvents: AnyObject {

    /// `listsDesktop`: the app lists a desktop among its windows (Finder).
    func appWindows(_ found: [AppWindow], pid: pid_t, adopting: Bool, listsDesktop: Bool)
    func windowAppeared(_ w: AppWindow)
    func windowGone(_ id: WindowID, listed: [AppWindow])
    func windowMinimized(_ id: WindowID)
    func titleChanged(_ id: WindowID, _ title: String)
    func focusChanged(_ report: FocusReport, pid: pid_t)
    /// An app with no connection (a system prompt's) is frontmost now.
    func unmanagedAppActivated()
    func writeFailed(_ id: WindowID)
    func appAnswered(_ ids: Set<WindowID>)
    func startApps(_ pids: Set<pid_t>)
    func appTerminated(_ pid: pid_t)
    func appHidden(_ pid: pid_t)
}

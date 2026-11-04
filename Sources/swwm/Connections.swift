//
//  Connections.swift
//  swwm
//
//  Created by Yesset Murat on 04.11.2026.
//

import AppKit
import os
import SwwmCore

/// One `AppConnection` per manageable app: made when the app launches, when
/// swwm starts, or when an app swwm has none for shows a window; dropped
/// when the app quits. Turns NSWorkspace notifications into connection
/// calls and manager calls.
final class Connections {

    /// The AX callback is a C function; it reaches the connections through this.
    nonisolated(unsafe) static weak var current: Connections?

    private let ax = AXThread()
    private unowned let manager: Manager
    private let map = OSAllocatedUnfairLock(initialState: [pid_t: AppConnection]())
    private var startPids: Set<pid_t> = []  // main: apps running when swwm started
    private var tokens: [NSObjectProtocol] = []

    init(manager: Manager) {
        self.manager = manager
    }

    /// Any thread.
    func connection(_ pid: pid_t) -> AppConnection? { map.withLock { $0[pid] } }

    func start() {
        Connections.current = self
        let running = NSWorkspace.shared.runningApplications.filter(\.isManageable)
        startPids = Set(running.map(\.processIdentifier))
        manager.startApps(startPids)
        for app in running { connect(app) }
        let nc = NSWorkspace.shared.notificationCenter
        func on(_ name: Notification.Name, _ handle: @escaping (NSRunningApplication) -> Void) {
            tokens.append(nc.addObserver(forName: name, object: nil, queue: .main) { note in
                if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                    handle(app)
                }
            })
        }
        on(NSWorkspace.didLaunchApplicationNotification) { [weak self] app in
            if app.isManageable { self?.connect(app) }
        }
        on(NSWorkspace.didTerminateApplicationNotification) { [weak self] app in
            guard let self else { return }
            let pid = app.processIdentifier
            if let c = map.withLock({ $0.removeValue(forKey: pid) }) { ax.perform { c.disconnect() } }
            manager.appTerminated(pid)
        }
        on(NSWorkspace.didHideApplicationNotification) { [weak self] app in
            self?.manager.appHidden(app.processIdentifier)
        }
        on(NSWorkspace.didUnhideApplicationNotification) { [weak self] app in
            self?.connection(app.processIdentifier)?.rescan()
        }
        on(NSWorkspace.didActivateApplicationNotification) { [weak self] app in
            guard app.isManageable else { return }
            self?.connect(app)
            self?.connection(app.processIdentifier)?.readFocus()
        }
    }

    /// A window reached the screen: an app with no connection yet, or one
    /// that gave no answer before, is asked again.
    func serverEvent(_ e: WindowServerEvent) {
        guard case .added(let id) = e, let pid = WindowServer.window(id)?.pid,
              let app = NSRunningApplication(processIdentifier: pid), app.isManageable else { return }
        connect(app)
    }

    /// Main.
    private func connect(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        let c = map.withLock { map in
            if let c = map[pid] { return c }
            let c = AppConnection(app: app, ax: ax, events: manager, adopting: startPids.contains(pid))
            map[pid] = c
            return c
        }
        ax.perform { c.connect() }
    }
}

extension NSRunningApplication {

    /// Apps whose windows swwm manages: regular apps, and menu-bar (accessory)
    /// apps that open windows, such as 1Password. Not macOS's own accessory
    /// agents (the Touch ID and password prompts of coreautha and
    /// SecurityAgent, Notification Center), not background agents, not swwm.
    var isManageable: Bool {
        guard processIdentifier != getpid() else { return false }
        switch activationPolicy {
        case .regular: return true
        case .accessory: return bundleURL.map { !$0.path.hasPrefix("/System/") } ?? false
        default: return false
        }
    }
}

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
    private unowned let events: AppEvents
    private let map = OSAllocatedUnfairLock(initialState: [pid_t: AppConnection]())
    private var startPids: Set<pid_t> = []  // main: apps running when swwm started
    private var tokens: [NSObjectProtocol] = []
    let focusTicket = FocusTicket()
    private let screen = ScreenLock()

    init(events: AppEvents) {
        self.events = events
    }

    /// Any thread.
    func connection(_ pid: pid_t) -> AppConnection? { map.withLock { $0[pid] } }

    // Workaround: a hung app never answers, and quit must finish; this bounds
    // the wait for each app's queued writes.
    static let quitFlush: TimeInterval = 2

    /// Waits for every app's queued writes, all apps at once (quit).
    func flush() {
        let all = map.withLock { Array($0.values) }
        let group = DispatchGroup()
        for c in all { DispatchQueue.global().async(group: group) { c.flush(timeout: Self.quitFlush) } }
        group.wait()
    }

    func start() {
        Connections.current = self
        let running = NSWorkspace.shared.runningApplications.filter(\.isManageable)
        startPids = Set(running.map(\.processIdentifier))
        events.startApps(startPids)
        for app in running { connect(app) }
        // While the screen is locked apps list no windows: they are reported
        // once it is unlocked.
        let dnc = DistributedNotificationCenter.default()
        for (name, locked) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            tokens.append(dnc.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                screen.isLocked = locked
                if !locked { map.withLock { Array($0.values) }.forEach { $0.rescan() } }
            })
        }
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
            events.appTerminated(pid)
        }
        on(NSWorkspace.didHideApplicationNotification) { [weak self] app in
            self?.events.appHidden(app.processIdentifier)
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
            let c = AppConnection(app: app, ax: ax, events: events, adopting: startPids.contains(pid), focusTicket: focusTicket,
                                  screen: screen)
            map[pid] = c
            return c
        }
        ax.perform { c.connect() }
    }
}

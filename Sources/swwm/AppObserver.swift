//
//  AppObserver.swift
//  swwm
//
//  Created by Yesset Murat on 03.11.2026.
//

import AppKit
import ApplicationServices
import SwwmCore

/// Turns NSWorkspace and Accessibility notifications into Manager calls.
final class AppObserver {

    /// The AX callback is a C function; it reaches the manager through this.
    nonisolated(unsafe) static weak var current: AppObserver?

    private let manager: Manager
    private var observers: [pid_t: AXObserver] = [:]
    private var tokens: [NSObjectProtocol] = []

    init(manager: Manager) {
        self.manager = manager
    }

    func start() {
        AppObserver.current = self
        for app in NSWorkspace.shared.runningApplications where app.isManageable {
            observe(app)
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
            guard app.isManageable else { return }
            // A fresh app may not answer AX yet.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self?.observe(app)
                self?.manager.appShown(app)
            }
        }
        on(NSWorkspace.didTerminateApplicationNotification) { [weak self] app in
            self?.observers[app.processIdentifier] = nil
            self?.manager.appTerminated(app.processIdentifier)
        }
        on(NSWorkspace.didHideApplicationNotification) { [weak self] app in
            self?.manager.appHidden(app.processIdentifier)
        }
        on(NSWorkspace.didUnhideApplicationNotification) { [weak self] app in
            self?.manager.appShown(app)
        }
        on(NSWorkspace.didActivateApplicationNotification) { [weak self] app in
            self?.manager.appActivated(app)
        }
    }

    /// Registers for an app's window events; an app that is not ready for
    /// AX yet gets a few more tries.
    private func observe(_ app: NSRunningApplication, attempt: Int = 0) {
        let pid = app.processIdentifier
        guard observers[pid] == nil, !app.isTerminated else { return }
        var observer: AXObserver?
        guard AXObserverCreate(pid, axCallback, &observer) == .success, let observer else { return }
        let el = AXUIElementCreateApplication(pid)
        let created = AXObserverAddNotification(observer, el, kAXWindowCreatedNotification as CFString, nil)
        guard created == .success || created == .notificationAlreadyRegistered else {
            if attempt < 5 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                    self?.observe(app, attempt: attempt + 1)
                    self?.manager.appShown(app)
                }
            }
            return
        }
        observers[pid] = observer
        AXObserverAddNotification(observer, el, kAXFocusedWindowChangedNotification as CFString, nil)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        for w in AXWindow.windows(of: app) { watch(w) }
    }

    /// Window-level notifications carry the window ID as refcon: a destroyed
    /// element can no longer tell its ID.
    func watch(_ w: AXWindow) {
        guard let observer = observers[w.pid] else { return }
        let refcon = UnsafeMutableRawPointer(bitPattern: UInt(w.id))
        for n in [kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification,
                  kAXTitleChangedNotification] {
            AXObserverAddNotification(observer, w.element, n as CFString, refcon)
        }
    }

    fileprivate func handle(_ element: AXUIElement, _ notification: String, _ refcon: UnsafeMutableRawPointer?) {
        let id = refcon.map { WindowID(UInt(bitPattern: $0)) }
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        let app = NSRunningApplication(processIdentifier: pid)

        switch notification {
        case kAXWindowCreatedNotification:
            guard let app, let w = AXWindow(element, app: app) else { return }
            watch(w)
            manager.windowCreated(w)
        case kAXFocusedWindowChangedNotification:
            guard let app, let w = AXWindow(element, app: app) else { return }
            manager.windowFocusChanged(w)
        case kAXUIElementDestroyedNotification:
            if let id { manager.windowGone(id) }
        case kAXWindowMiniaturizedNotification:
            if let id { manager.windowMinimized(id) }
        case kAXTitleChangedNotification:
            if let id { manager.titleChanged(id, element.attribute(kAXTitleAttribute) ?? "") }
        case kAXWindowDeminiaturizedNotification:
            guard let app, let w = AXWindow(element, app: app) else { return }
            manager.windowCreated(w)
        default:
            break
        }
    }
}

private func axCallback(_ observer: AXObserver, _ element: AXUIElement, _ notification: CFString,
                        _ refcon: UnsafeMutableRawPointer?) {
    AppObserver.current?.handle(element, notification as String, refcon)
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

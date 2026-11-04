//
//  AppObserver.swift
//  swwm
//
//  Created by Yesset Murat on 03.11.2026.
//

import AppKit
import ApplicationServices
import SwwmCore

/// A thread with its own run loop for Accessibility notifications and the
/// reads that follow them: an app answers AX only once it is free, and the
/// main thread (the window-server events, the bar, layout) must not wait for
/// it meanwhile.
final class AXThread {

    private var runLoop: CFRunLoop?

    init() {
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [self] in
            runLoop = CFRunLoopGetCurrent()
            // A run loop with no source returns at once: keep a port in it.
            let keep = CFMachPortCreate(nil, { _, _, _, _ in }, nil, nil)
            CFRunLoopAddSource(runLoop, CFMachPortCreateRunLoopSource(nil, keep, 0), .commonModes)
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "dev.swwm.ax"
        thread.start()
        ready.wait()
    }

    func perform(_ block: @escaping () -> Void) {
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue, block)
        CFRunLoopWakeUp(runLoop)
    }

    func add(_ source: CFRunLoopSource) { CFRunLoopAddSource(runLoop, source, .commonModes) }

    func remove(_ source: CFRunLoopSource) { CFRunLoopRemoveSource(runLoop, source, .commonModes) }
}

/// Turns NSWorkspace and Accessibility notifications into Manager calls.
/// Everything that talks AX to apps here runs on the AX thread; Manager is
/// called on the main thread with what was read.
final class AppObserver {

    /// The AX callback is a C function; it reaches the observer through this.
    nonisolated(unsafe) static weak var current: AppObserver?

    private let manager: Manager
    private let ax = AXThread()
    private var observers: [pid_t: AXObserver] = [:]  // AX thread only
    private var tokens: [NSObjectProtocol] = []

    init(manager: Manager) {
        self.manager = manager
    }

    func start() {
        AppObserver.current = self
        for app in NSWorkspace.shared.runningApplications where app.isManageable {
            ax.perform { [self] in observe(app) }
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
            guard let self, app.isManageable else { return }
            // Right away: a window shown before swwm watches the app sits at the
            // app's spot until it is found. `observe` retries while AX is not ready.
            ax.perform {
                self.observe(app)
                self.rescan(app)
            }
            // A slow app (Xcode) shows its first window before its window events
            // reach swwm: look again a few times; known windows are skipped.
            for delay in [0.5, 1.5, 3, 6] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self.ax.perform { self.rescan(app) } }
            }
        }
        on(NSWorkspace.didTerminateApplicationNotification) { [weak self] app in
            guard let self else { return }
            let pid = app.processIdentifier
            ax.perform {
                if let o = self.observers.removeValue(forKey: pid) { self.ax.remove(AXObserverGetRunLoopSource(o)) }
            }
            manager.appTerminated(pid)
        }
        on(NSWorkspace.didHideApplicationNotification) { [weak self] app in
            self?.manager.appHidden(app.processIdentifier)
        }
        on(NSWorkspace.didUnhideApplicationNotification) { [weak self] app in
            guard let self else { return }
            ax.perform { self.rescan(app) }
        }
        on(NSWorkspace.didActivateApplicationNotification) { [weak self] app in
            guard let self else { return }
            ax.perform {
                let el = AXUIElementCreateApplication(app.processIdentifier)
                guard let win: AXUIElement = el.attribute(kAXFocusedWindowAttribute),
                      let w = AXWindow(win, app: app) else { return }
                self.focusChanged(w)
            }
        }
    }

    /// Registers for an app's window events; an app that is not ready for
    /// AX yet gets more tries, often, for about 5 s. AX thread.
    private func observe(_ app: NSRunningApplication, attempt: Int = 0) {
        let pid = app.processIdentifier
        guard observers[pid] == nil, !app.isTerminated else { return }
        var observer: AXObserver?
        guard AXObserverCreate(pid, axCallback, &observer) == .success, let observer else { return }
        let el = AXUIElementCreateApplication(pid)
        let created = AXObserverAddNotification(observer, el, kAXWindowCreatedNotification as CFString, nil)
        guard created == .success || created == .notificationAlreadyRegistered else {
            if attempt < 50 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.ax.perform {
                        self?.observe(app, attempt: attempt + 1)
                        self?.rescan(app)
                    }
                }
            }
            return
        }
        observers[pid] = observer
        AXObserverAddNotification(observer, el, kAXFocusedWindowChangedNotification as CFString, nil)
        // Switching native tabs reports only a main window change.
        AXObserverAddNotification(observer, el, kAXMainWindowChangedNotification as CFString, nil)
        ax.add(AXObserverGetRunLoopSource(observer))
        for w in AXWindow.windows(of: app) { watchHere(w) }
    }

    /// Window-level notifications carry the window ID as refcon: a destroyed
    /// element can no longer tell its ID. Any thread.
    func watch(_ w: AXWindow) {
        ax.perform { [self] in watchHere(w) }
    }

    private func watchHere(_ w: AXWindow) {
        guard let observer = observers[w.pid] else { return }
        let refcon = UnsafeMutableRawPointer(bitPattern: UInt(w.id))
        for n in [kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification,
                  kAXTitleChangedNotification] {
            AXObserverAddNotification(observer, w.element, n as CFString, refcon)
        }
    }

    /// The app's windows, read here and handed to the manager. AX thread.
    private func rescan(_ app: NSRunningApplication) {
        let found = AXWindow.windows(of: app).map { (window: $0, facts: WindowFacts($0)) }
        DispatchQueue.main.async { [manager] in manager.rescan(found) }
    }

    /// AX thread.
    private func focusChanged(_ w: AXWindow) {
        let facts = WindowFacts(w)
        DispatchQueue.main.async { [manager] in manager.windowFocusChanged(w, facts: facts) }
    }

    /// AX thread.
    fileprivate func handle(_ element: AXUIElement, _ notification: String, _ refcon: UnsafeMutableRawPointer?) {
        let id = refcon.map { WindowID(UInt(bitPattern: $0)) }
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        let app = NSRunningApplication(processIdentifier: pid)

        switch notification {
        case kAXWindowCreatedNotification, kAXWindowDeminiaturizedNotification:
            guard let app, let w = AXWindow(element, app: app) else { return }
            watchHere(w)
            let facts = WindowFacts(w)
            DispatchQueue.main.async { [manager] in manager.windowCreated(w, facts: facts) }
        case kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification:
            guard let app, let w = AXWindow(element, app: app) else { return }
            focusChanged(w)
        case kAXUIElementDestroyedNotification:
            if let id { DispatchQueue.main.async { [manager] in manager.windowGone(id) } }
        case kAXWindowMiniaturizedNotification:
            if let id { DispatchQueue.main.async { [manager] in manager.windowMinimized(id) } }
        case kAXTitleChangedNotification:
            guard let id else { return }
            let title: String = element.attribute(kAXTitleAttribute) ?? ""
            DispatchQueue.main.async { [manager] in manager.titleChanged(id, title) }
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

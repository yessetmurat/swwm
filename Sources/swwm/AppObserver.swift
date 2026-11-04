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
/// The observers live on the AX thread; every AX call to an app runs on
/// that app's own queue and waits for the app's answer, so a busy app
/// (Xcode launching) delays only its own events and none get lost. Manager
/// is called on the main thread with what was read, in the app's order.
final class AppObserver {

    /// The AX callback is a C function; it reaches the observer through this.
    nonisolated(unsafe) static weak var current: AppObserver?

    private struct App {

        let queue: DispatchQueue
        var observer: AXObserver?
        var registering = false
    }

    private let manager: Manager
    private let ax = AXThread()
    private var apps: [pid_t: App] = [:]  // AX thread only
    private var tokens: [NSObjectProtocol] = []
    /// How long a call waits for an app's answer: only a hung app takes this long.
    private static let answerTimeout: Float = 30

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
            ax.perform { self.observe(app) }
        }
        on(NSWorkspace.didTerminateApplicationNotification) { [weak self] app in
            guard let self else { return }
            let pid = app.processIdentifier
            ax.perform {
                if let o = self.apps.removeValue(forKey: pid)?.observer { self.ax.remove(AXObserverGetRunLoopSource(o)) }
            }
            manager.appTerminated(pid)
        }
        on(NSWorkspace.didHideApplicationNotification) { [weak self] app in
            self?.manager.appHidden(app.processIdentifier)
        }
        on(NSWorkspace.didUnhideApplicationNotification) { [weak self] app in
            self?.onAppQueue(app) { [weak self] in
                let found = Self.windows(of: app)
                DispatchQueue.main.async { self?.manager.rescan(found) }
            }
        }
        on(NSWorkspace.didActivateApplicationNotification) { [weak self] app in
            self?.onAppQueue(app) { [weak self] in
                let el = AXUIElementCreateApplication(app.processIdentifier)
                guard let win: AXUIElement = Self.patiently(el, { el.attribute(kAXFocusedWindowAttribute) }) else { return }
                self?.focusChanged(win, app: app)
            }
        }
    }

    /// A window reached the screen. An app swwm does not watch yet (it gave
    /// no answer at launch) is asked again.
    func serverEvent(_ e: WindowServerEvent) {
        guard case .added(let id) = e, let pid = WindowServer.window(id)?.pid,
              let app = NSRunningApplication(processIdentifier: pid), app.isManageable else { return }
        ax.perform { [self] in observe(app) }
    }

    /// Registers for an app's window events, then hands its windows to the
    /// manager: one shown before that sits at the app's spot until found. AX
    /// thread.
    private func observe(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        if apps[pid] == nil { apps[pid] = App(queue: DispatchQueue(label: "dev.swwm.ax.\(pid)")) }
        guard let entry = apps[pid], entry.observer == nil, !entry.registering, !app.isTerminated else { return }
        apps[pid]?.registering = true
        entry.queue.async { [self] in
            let observer = Self.register(pid)
            let found = observer == nil ? [] : Self.windows(of: app)
            if let observer { for f in found { Self.watch(f.window, with: observer) } }
            ax.perform { [self] in
                guard apps[pid] != nil else { return }  // quit meanwhile
                apps[pid]?.registering = false
                guard let observer else {
                    log.debug("observe \(app.localizedName ?? "?", privacy: .public): no answer")
                    return
                }
                apps[pid]?.observer = observer
                ax.add(AXObserverGetRunLoopSource(observer))
                DispatchQueue.main.async { [manager] in manager.rescan(found) }
            }
        }
    }

    /// An observer for the app's window events, once the app answers.
    private static func register(_ pid: pid_t) -> AXObserver? {
        var observer: AXObserver?
        guard AXObserverCreate(pid, axCallback, &observer) == .success, let observer else { return nil }
        let el = AXUIElementCreateApplication(pid)
        return patiently(el) {
            let created = AXObserverAddNotification(observer, el, kAXWindowCreatedNotification as CFString, nil)
            guard created == .success || created == .notificationAlreadyRegistered else {
                log.debug("register \(pid, privacy: .public): \(created.rawValue, privacy: .public)")
                return nil
            }
            AXObserverAddNotification(observer, el, kAXFocusedWindowChangedNotification as CFString, nil)
            // Switching native tabs reports only a main window change.
            AXObserverAddNotification(observer, el, kAXMainWindowChangedNotification as CFString, nil)
            return observer
        }
    }

    /// Runs `body` on the app's queue, after what is queued for it. AX
    /// thread or main.
    private func onAppQueue(_ app: NSRunningApplication, _ body: @escaping () -> Void) {
        guard app.isManageable else { return }
        ax.perform { [self] in
            observe(app)
            apps[app.processIdentifier]?.queue.async(execute: body)
        }
    }

    /// Window-level notifications carry the window ID as refcon: a destroyed
    /// element can no longer tell its ID. Any thread.
    func watch(_ w: AXWindow) {
        ax.perform { [self] in
            guard let entry = apps[w.pid], let observer = entry.observer else { return }
            entry.queue.async { Self.watch(w, with: observer) }
        }
    }

    private static func watch(_ w: AXWindow, with observer: AXObserver) {
        let refcon = UnsafeMutableRawPointer(bitPattern: UInt(w.id))
        patiently(w.element) {
            for n in [kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification,
                      kAXWindowDeminiaturizedNotification, kAXTitleChangedNotification] {
                AXObserverAddNotification(observer, w.element, n as CFString, refcon)
            }
        }
    }

    /// The app's windows with what decides whether swwm manages them. App queue.
    private static func windows(of app: NSRunningApplication) -> [(window: AXWindow, facts: WindowFacts)] {
        let el = AXUIElementCreateApplication(app.processIdentifier)
        let list: [AXUIElement] = patiently(el) { el.attribute(kAXWindowsAttribute) ?? [] }
        return list.compactMap { e in patiently(e) { AXWindow(e, app: app).map { ($0, WindowFacts($0)) } } }
    }

    /// Waits for the app's answer instead of the global timeout, which keeps
    /// the main thread from waiting on a hung app; the element is back on the
    /// global timeout before the main thread gets it.
    @discardableResult
    private static func patiently<T>(_ e: AXUIElement, _ body: () -> T) -> T {
        AXUIElementSetMessagingTimeout(e, answerTimeout)
        defer { AXUIElementSetMessagingTimeout(e, 0) }
        return body()
    }

    /// App queue.
    private func focusChanged(_ element: AXUIElement, app: NSRunningApplication) {
        guard let (w, facts) = Self.read(element, app: app, for: "focus") else { return }
        DispatchQueue.main.async { [manager] in manager.windowFocusChanged(w, facts: facts) }
    }

    /// A window element's id and facts, waiting for the app. App queue.
    private static func read(_ element: AXUIElement, app: NSRunningApplication, for what: String) -> (AXWindow, WindowFacts)? {
        patiently(element) {
            guard let w = AXWindow(element, app: app) else {
                var id: CGWindowID = 0
                let error = _AXUIElementGetWindow(element, &id)
                log.debug("\(what, privacy: .public) of \(app.localizedName ?? "?", privacy: .public): no window number (\(error.rawValue, privacy: .public))")
                return nil
            }
            return (w, WindowFacts(w))
        }
    }

    /// AX thread: the work goes to the app's queue, in order.
    fileprivate func handle(_ element: AXUIElement, _ notification: String, _ refcon: UnsafeMutableRawPointer?) {
        let id = refcon.map { WindowID(UInt(bitPattern: $0)) }
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        guard let entry = apps[pid], let observer = entry.observer,
              let app = NSRunningApplication(processIdentifier: pid) else { return }
        entry.queue.async { [self] in
            switch notification {
            case kAXWindowCreatedNotification, kAXWindowDeminiaturizedNotification:
                guard let (w, facts) = Self.read(element, app: app, for: notification) else { return }
                Self.watch(w, with: observer)
                DispatchQueue.main.async { [manager] in manager.windowCreated(w, facts: facts) }
            case kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification:
                focusChanged(element, app: app)
            case kAXUIElementDestroyedNotification:
                if let id { DispatchQueue.main.async { [manager] in manager.windowGone(id) } }
            case kAXWindowMiniaturizedNotification:
                if let id { DispatchQueue.main.async { [manager] in manager.windowMinimized(id) } }
            case kAXTitleChangedNotification:
                guard let id else { return }
                let title: String = Self.patiently(element) { element.attribute(kAXTitleAttribute) ?? "" }
                DispatchQueue.main.async { [manager] in manager.titleChanged(id, title) }
            default:
                break
            }
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

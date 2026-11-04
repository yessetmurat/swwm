//
//  AppConnection.swift
//  swwm
//
//  Created by Yesset Murat on 04.11.2026.
//

import AppKit
import ApplicationServices
import SwwmCore

/// A thread with its own run loop for the Accessibility observers. It only
/// routes notifications to the app connections; it never waits on an app.
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

/// What an app reported about one window, with its element for the writes
/// swwm still makes on main.
struct Reported {

    let window: AppWindow
    let element: AXUIElement
}

/// What app connections tell the manager, on the main thread, in each app's
/// order.
protocol AppEvents: AnyObject {

    func appWindows(_ found: [Reported], pid: pid_t, adopting: Bool)
    func windowAppeared(_ r: Reported)
    func windowGone(_ id: WindowID, listed: [Reported])
    func windowMinimized(_ id: WindowID)
    func titleChanged(_ id: WindowID, _ title: String)
    func focusChanged(_ r: Reported?, pid: pid_t)
}

/// Everything swwm says to one app goes through here, on the app's own
/// queue, waiting for the app's answer: a busy app (Xcode launching) delays
/// only its own windows and none of its events get lost. What was read goes
/// to the manager as plain values.
final class AppConnection {

    let app: NSRunningApplication
    var pid: pid_t { app.processIdentifier }
    private let ax: AXThread
    private weak var events: AppEvents?
    private let queue: DispatchQueue
    private var adopting: Bool                     // AX thread: the app ran when swwm started
    private var observer: AXObserver?              // AX thread
    private var registering = false                // AX thread
    private var watcher: AXObserver?               // queue: the same observer, for window notifications
    private var elements: [WindowID: AXUIElement] = [:]  // queue
    private var watched: Set<WindowID> = []        // queue
    /// How long a call waits for the app's answer: only a hung app takes this long.
    static let answerTimeout: Float = 30

    init(app: NSRunningApplication, ax: AXThread, events: AppEvents, adopting: Bool) {
        self.app = app
        self.ax = ax
        self.events = events
        self.adopting = adopting
        queue = DispatchQueue(label: "dev.swwm.app.\(app.processIdentifier)")
    }

    /// Registers for the app's window events once it answers, then reports
    /// its windows: one shown before that sits at the app's spot until found.
    /// An app that gave no answer is asked again at its next window event. AX
    /// thread.
    func connect() {
        guard observer == nil, !registering, !app.isTerminated else { return }
        registering = true
        queue.async { [self] in
            let observer = Self.register(pid)
            watcher = observer
            let found = observer == nil ? [] : listed()
            ax.perform { [self] in
                registering = false
                guard let observer, !app.isTerminated else {
                    log.debug("connect \(self.app.localizedName ?? "?", privacy: .public): no answer")
                    return
                }
                self.observer = observer
                ax.add(AXObserverGetRunLoopSource(observer))
                let adopting = self.adopting
                self.adopting = false
                DispatchQueue.main.async { [self] in events?.appWindows(found, pid: pid, adopting: adopting) }
            }
        }
    }

    /// The app quit. AX thread.
    func disconnect() {
        if let observer { ax.remove(AXObserverGetRunLoopSource(observer)) }
        observer = nil
    }

    /// Reports the app's windows again (the app was unhidden).
    func rescan() {
        queue.async { [self] in
            let found = listed()
            DispatchQueue.main.async { [self] in events?.appWindows(found, pid: pid, adopting: false) }
        }
    }

    /// Reports the app's focused window (the app was activated).
    func readFocus() {
        queue.async { [self] in
            let el = AXUIElementCreateApplication(pid)
            let win: AXUIElement? = Self.patiently(el) { el.attribute(kAXFocusedWindowAttribute) }
            let r = win.flatMap { report($0, listed: nil) }
            DispatchQueue.main.async { [self] in events?.focusChanged(r, pid: pid) }
        }
    }

    /// The window's frame as the app has it now; nil for a window it no
    /// longer lists. `reply` runs on main.
    func readFrame(_ id: WindowID, reply: @escaping (CGRect?) -> Void) {
        queue.async { [self] in
            let frame = elements[id].map { e in Self.patiently(e) { AXWindow(element: e, pid: pid, id: id, appName: "").frame } }
            DispatchQueue.main.async { reply(frame) }
        }
    }

    /// An AX notification of this app. AX thread; the work goes to the queue,
    /// in order.
    func handle(_ element: AXUIElement, _ notification: String, _ refcon: UnsafeMutableRawPointer?) {
        let id = refcon.map { WindowID(UInt(bitPattern: $0)) }
        queue.async { [self] in
            switch notification {
            case kAXWindowCreatedNotification, kAXWindowDeminiaturizedNotification:
                guard let r = report(element, listed: nil) else { return }
                DispatchQueue.main.async { [self] in events?.windowAppeared(r) }
            case kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification:
                let r = report(element, listed: nil)
                DispatchQueue.main.async { [self] in events?.focusChanged(r, pid: pid) }
            case kAXUIElementDestroyedNotification:
                guard let id else { return }
                elements[id] = nil
                watched.remove(id)
                let rest = listed()
                DispatchQueue.main.async { [self] in events?.windowGone(id, listed: rest) }
            case kAXWindowMiniaturizedNotification:
                if let id { DispatchQueue.main.async { [self] in events?.windowMinimized(id) } }
            case kAXTitleChangedNotification:
                guard let id else { return }
                let title: String = Self.patiently(element) { element.attribute(kAXTitleAttribute) ?? "" }
                DispatchQueue.main.async { [self] in events?.titleChanged(id, title) }
            default:
                break
            }
        }
    }

    // MARK: - Queue

    /// The app's listed windows, as reports. Queue.
    private func listed() -> [Reported] {
        let el = AXUIElementCreateApplication(pid)
        let list: [AXUIElement] = Self.patiently(el) { el.attribute(kAXWindowsAttribute) ?? [] }
        let ids = Set(list.compactMap(Self.windowID))
        return list.compactMap { report($0, listed: ids) }
    }

    /// One window as a report, watched from now on. `listed` nil: read the
    /// app's list too. Queue.
    private func report(_ e: AXUIElement, listed: Set<WindowID>?) -> Reported? {
        guard let id = Self.patiently(e, { Self.windowID(e) }) else {
            var n: CGWindowID = 0
            log.debug("\(self.app.localizedName ?? "?", privacy: .public): no window number (\(_AXUIElementGetWindow(e, &n).rawValue, privacy: .public))")
            return nil
        }
        let ids = listed ?? {
            let el = AXUIElementCreateApplication(pid)
            let list: [AXUIElement] = Self.patiently(el) { el.attribute(kAXWindowsAttribute) ?? [] }
            return Set(list.compactMap(Self.windowID))
        }()
        let window = Self.patiently(e) { () -> AppWindow in
            let w = AXWindow(element: e, pid: pid, id: id, appName: app.localizedName ?? "")
            let button: AXUIElement? = e.attribute(kAXFullScreenButtonAttribute)
            return AppWindow(id: id, pid: pid, app: w.appName, title: w.title, frame: w.frame,
                             layer: WindowServer.window(id)?.layer ?? 0, role: e.attribute(kAXRoleAttribute),
                             subrole: e.attribute(kAXSubroleAttribute), isFullScreen: w.isFullScreen,
                             isMinimized: w.isMinimized, isResizable: w.isResizable, hasFullScreenButton: button != nil,
                             listed: ids)
        }
        elements[id] = e
        watch(e, id)
        return Reported(window: window, element: e)
    }

    /// Window-level notifications carry the window ID as refcon: a destroyed
    /// element can no longer tell its ID. Queue.
    private func watch(_ e: AXUIElement, _ id: WindowID) {
        guard let watcher, watched.insert(id).inserted else { return }
        let refcon = UnsafeMutableRawPointer(bitPattern: UInt(id))
        Self.patiently(e) {
            for n in [kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification,
                      kAXWindowDeminiaturizedNotification, kAXTitleChangedNotification] {
                AXObserverAddNotification(watcher, e, n as CFString, refcon)
            }
        }
    }

    private static func windowID(_ e: AXUIElement) -> WindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(e, &id) == .success && id != 0 ? id : nil
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

    /// Waits for the app's answer instead of the global timeout, which keeps
    /// the main thread from waiting on a hung app; the element is back on the
    /// global timeout before the main thread gets it.
    @discardableResult
    static func patiently<T>(_ e: AXUIElement, _ body: () -> T) -> T {
        AXUIElementSetMessagingTimeout(e, answerTimeout)
        defer { AXUIElementSetMessagingTimeout(e, 0) }
        return body()
    }
}

private func axCallback(_ observer: AXObserver, _ element: AXUIElement, _ notification: CFString,
                        _ refcon: UnsafeMutableRawPointer?) {
    var pid: pid_t = 0
    AXUIElementGetPid(element, &pid)
    Connections.current?.connection(pid)?.handle(element, notification as String, refcon)
}

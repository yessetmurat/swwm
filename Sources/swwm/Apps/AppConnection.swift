//
//  AppConnection.swift
//  swwm
//
//  Created by Yesset Murat on 04.11.2026.
//

import AppKit
import ApplicationServices
import SwwmCore

/// Everything swwm says to one app goes through here, on the app's own
/// queue, waiting for the app's answer: a busy app (Xcode launching) delays
/// only its own windows and none of its events get lost, and the main
/// thread never waits for it. What was read goes to the manager as plain
/// values; commands return at once.
final class AppConnection {

    let app: NSRunningApplication
    var pid: pid_t { app.processIdentifier }
    private let ax: AXThread
    private weak var events: AppEvents?
    private let queue: DispatchQueue
    private let adopting: Bool                     // the app ran when swwm started
    private var reported = false                   // queue: its windows went to the manager once
    private var observer: AXObserver?              // AX thread
    private var registering = false                // AX thread
    private var watcher: AXObserver?               // queue: the same observer, for window notifications
    private var elements: [WindowID: AXUIElement] = [:]  // queue
    private var watched: Set<WindowID> = []        // queue
    private let writes = PendingWrites<WindowWrite>()
    private var answers = AnswerWatch()            // queue
    private let focusTicket: FocusTicket
    private let screen: ScreenLock
    /// How long a call waits for the app's answer: only a hung app takes this long.
    // Workaround: nothing tells swwm that an app hangs (the window server's
    // unresponsive-app query said no for a stopped and for a hung app in a
    // test on 2026-11-04), so a call gives up after this. A focus park waits
    // this long for a hung app's window it hid.
    static let answerTimeout: Float = 30

    init(
        app: NSRunningApplication,
        ax: AXThread,
        events: AppEvents,
        adopting: Bool,
        focusTicket: FocusTicket,
        screen: ScreenLock
    ) {
        self.screen = screen
        self.app = app
        self.ax = ax
        self.events = events
        self.adopting = adopting
        self.focusTicket = focusTicket
        queue = DispatchQueue(label: "dev.swwm.app.\(app.processIdentifier)")
    }

    /// Registers for the app's window events once it answers, then reports
    /// its windows: one shown before that sits at the app's spot until found.
    /// An app that gave no answer is asked again at its next window event. AX
    /// thread.
    func connect() {
        guard observer == nil, !registering, !app.isTerminated else {
            return
        }

        registering = true
        queue.async { [self] in
            let observer = Self.register(pid)
            watcher = observer
            if observer != nil { reportWindows() }

            ax.perform { [self] in
                registering = false

                guard let observer, !app.isTerminated else {
                    log.debug("connect \(self.app.localizedName ?? "?", privacy: .public): no answer")
                    return
                }

                self.observer = observer
                ax.add(AXObserverGetRunLoopSource(observer))
            }
        }
    }

    /// The app quit. AX thread.
    func disconnect() {
        if let observer { ax.remove(AXObserverGetRunLoopSource(observer)) }
        observer = nil
    }

    /// Reports the app's windows again (the app was unhidden, the screen
    /// was unlocked).
    func rescan() {
        queue.async { [self] in reportWindows() }
    }

    /// The app's windows to the manager; the first report of an app that ran
    /// when swwm started adopts them. Not while the screen is locked: apps
    /// list no windows then (AX hands out the app element for each). Queue.
    private func reportWindows() {
        guard watcher != nil, !screen.isLocked else {
            return
        }

        let found = listed()
        let adopt = adopting && !reported
        reported = true

        DispatchQueue.main.async { [self] in events?.appWindows(found, pid: pid, adopting: adopt) }
    }

    /// Reports the app's focused window (the app was activated).
    func readFocus() {
        queue.async { [self] in
            let el = AXUIElementCreateApplication(pid)
            let win: AXUIElement? = Self.patiently(el) { el.attribute(kAXFocusedWindowAttribute) }
            let w = win.flatMap { report($0, listed: nil) }

            DispatchQueue.main.async { [self] in events?.focusChanged(w, pid: pid) }
        }
    }

    /// The window's frame as the app has it now; nil for a window it no
    /// longer lists. `reply` runs on main.
    func readFrame(_ id: WindowID, reply: @escaping (CGRect?) -> Void) {
        queue.async { [self] in
            let frame = window(id).flatMap { w in Self.patiently(w.element) { w.frame } }
            if frame != nil { answered() }

            DispatchQueue.main.async { reply(frame) }
        }
    }

    // MARK: - Commands

    func setFrame(_ id: WindowID, _ r: CGRect) { write(id, .frame(r)) }

    func setPosition(_ id: WindowID, _ p: CGPoint) { write(id, .position(p)) }

    /// A write not started yet is replaced by a newer one. One the app did
    /// not take is reported: the window stays where it was.
    private func write(_ id: WindowID, _ w: WindowWrite) {
        guard writes.put(id, w) else {
            return
        }

        queue.async { [self] in
            guard let next = writes.take(id), let win = window(id) else {
                return
            }

            let result = Self.patiently(win.element) { () -> AXError in
                switch next {
                case .frame(let r): return win.setFrame(r)
                case .position(let p): return win.setPosition(p)
                }
            }

            switch result {
            case .success:
                answered()
            case .cannotComplete:  // no answer in time: placed again once the app answers
                answers.noAnswer(id)
                DispatchQueue.main.async { [self] in events?.writeFailed(id) }
            default:               // turned down: the window stays where it is
                DispatchQueue.main.async { [self] in events?.writeFailed(id) }
            }
        }
    }

    func raise(_ id: WindowID) {
        queue.async { [self] in
            guard let w = window(id) else {
                return
            }

            Self.patiently(w.element) { w.raise() }
        }
    }

    /// Focuses the window, unless focus moved on since `ticket` was taken.
    func focus(_ id: WindowID, ticket: Int) {
        queue.async { [self] in
            guard let w = window(id) else {
                return
            }

            Self.patiently(w.element) { focusTicket.run(ticket, w.focusSteps) }
        }
    }

    /// Which axes of the window take a new size; `reply` runs on main.
    func probeAxes(_ id: WindowID, reply: @escaping (_ width: Bool, _ height: Bool) -> Void) {
        queue.async { [self] in
            let axes = window(id).map { w in Self.patiently(w.element) { w.resizableAxes() } } ?? (false, false)
            DispatchQueue.main.async { reply(axes.0, axes.1) }
        }
    }

    /// Waits until the commands sent so far ran, at most `timeout` (quit).
    func flush(timeout: TimeInterval) {
        let done = DispatchSemaphore(value: 0)
        queue.async { done.signal() }
        _ = done.wait(timeout: .now() + timeout)
    }

    /// The app answered: windows whose writes it left unanswered are placed
    /// again. Queue.
    private func answered() {
        let ids = answers.answered()
        guard !ids.isEmpty else {
            return
        }

        DispatchQueue.main.async { [self] in events?.appAnswered(ids) }
    }

    /// A window the app reported, for commands. Queue.
    private func window(_ id: WindowID) -> AXWindow? {
        elements[id].map { AXWindow(
            element: $0,
            pid: pid,
            id: id,
            appName: app.localizedName ?? ""
        ) }
    }

    /// An AX notification of this app. AX thread; the work goes to the queue,
    /// in order.
    func handle(_ element: AXUIElement, _ notification: String, _ refcon: UnsafeMutableRawPointer?) {
        let id = refcon.map { WindowID(UInt(bitPattern: $0)) }

        queue.async { [self] in
            switch notification {
            case kAXWindowCreatedNotification, kAXWindowDeminiaturizedNotification:
                guard let w = report(element, listed: nil) else {
                    return
                }

                DispatchQueue.main.async { [self] in events?.windowAppeared(w) }
            case kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification:
                let w = report(element, listed: nil)
                DispatchQueue.main.async { [self] in events?.focusChanged(w, pid: pid) }
            case kAXUIElementDestroyedNotification:
                guard let id else {
                    return
                }

                elements[id] = nil
                watched.remove(id)
                writes.forget(id)

                let rest = listed()
                DispatchQueue.main.async { [self] in events?.windowGone(id, listed: rest) }
            case kAXWindowMiniaturizedNotification:
                if let id { DispatchQueue.main.async { [self] in events?.windowMinimized(id) } }
            case kAXTitleChangedNotification:
                guard let id else {
                    return
                }

                let title: String = Self.patiently(element) { element.attribute(kAXTitleAttribute) ?? "" }
                DispatchQueue.main.async { [self] in events?.titleChanged(id, title) }
            default:
                break
            }
        }
    }

    // MARK: - Queue

    /// The app's listed windows, as reports. Queue.
    private func listed() -> [AppWindow] {
        let el = AXUIElementCreateApplication(pid)
        let list: [AXUIElement] = Self.patiently(el) { el.attribute(kAXWindowsAttribute) ?? [] }
        let ids = Set(list.compactMap(Self.windowID))

        return list.compactMap { report($0, listed: ids) }
    }

    /// One window as a report, watched from now on. `listed` nil: read the
    /// app's list too. Queue.
    private func report(_ e: AXUIElement, listed: Set<WindowID>?) -> AppWindow? {
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
            let w = AXWindow(
                element: e,
                pid: pid,
                id: id,
                appName: app.localizedName ?? ""
            )
            let button: AXUIElement? = e.attribute(kAXFullScreenButtonAttribute)
            return AppWindow(
                id: id,
                pid: pid,
                app: w.appName,
                title: w.title,
                frame: w.frame ?? .zero,
                layer: WindowServer.window(id)?.layer ?? 0,
                role: e.attribute(kAXRoleAttribute),
                subrole: e.attribute(kAXSubroleAttribute),
                isFullScreen: w.isFullScreen,
                isMinimized: w.isMinimized,
                isResizable: w.isResizable,
                hasFullScreenButton: button != nil,
                listed: ids
            )
        }

        elements[id] = e
        watch(e, id)
        return window
    }

    /// Window-level notifications carry the window ID as refcon: a destroyed
    /// element can no longer tell its ID. Queue.
    private func watch(_ e: AXUIElement, _ id: WindowID) {
        guard let watcher, watched.insert(id).inserted else {
            return
        }

        let refcon = UnsafeMutableRawPointer(bitPattern: UInt(id))
        Self.patiently(e) {
            for n in [kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification,
                      kAXWindowDeminiaturizedNotification, kAXTitleChangedNotification] {
                AXObserverAddNotification(
                    watcher,
                    e,
                    n as CFString,
                    refcon
                )
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
        guard AXObserverCreate(pid, axCallback, &observer) == .success, let observer else {
            return nil
        }

        let el = AXUIElementCreateApplication(pid)
        return patiently(el) {
            let created = AXObserverAddNotification(
                observer,
                el,
                kAXWindowCreatedNotification as CFString,
                nil
            )
            guard created == .success || created == .notificationAlreadyRegistered else {
                log.debug("register \(pid, privacy: .public): \(created.rawValue, privacy: .public)")
                return nil
            }

            AXObserverAddNotification(
                observer,
                el,
                kAXFocusedWindowChangedNotification as CFString,
                nil
            )
            // Switching native tabs reports only a main window change.
            AXObserverAddNotification(
                observer,
                el,
                kAXMainWindowChangedNotification as CFString,
                nil
            )
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

private func axCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    var pid: pid_t = 0
    AXUIElementGetPid(element, &pid)

    Connections.current?.connection(pid)?.handle(element, notification as String, refcon)
}

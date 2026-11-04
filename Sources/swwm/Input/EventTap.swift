//
//  EventTap.swift
//  swwm
//
//  Created by Yesset Murat on 03.11.2026.
//

import AppKit
import SwwmCore

/// One session event tap for hotkeys (including cmd-tab), focus follows
/// mouse, and modifier+drag move/resize. It runs on its own thread and
/// decides from `TapState`, so system input never waits for the main
/// thread; the work it decides on runs on main.
final class EventTap {

    private struct Drag {

        let window: WindowID
        let resize: Bool
        let floating: Bool
        let start: CGPoint
        let frame: CGRect
    }

    private let manager: Manager
    let state = TapStateBox()
    private var port: CFMachPort?
    // Tap thread only.
    private var drag: Drag?
    private var press: (window: WindowID, frame: CGRect, point: CGPoint, clicks: Int)?  // plain left press on a managed window
    private var lastHover = Date.distantPast
    var onMouseMoved: (CGPoint) -> Void = { _ in }

    init(manager: Manager) {
        self.manager = manager
    }

    func update(config: Config) {
        let bindings = config.bindings, settings = config.settings
        state.update {
            $0.bindings = bindings
            $0.settings = settings
        }
    }

    func start() {
        let types: [CGEventType] = [.keyDown, .mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp,
                                    .rightMouseDown, .rightMouseDragged, .rightMouseUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }

        port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: tapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        guard let port else {
            NSLog("swwm: cannot create the event tap; is Accessibility granted?")
            return
        }

        let thread = Thread {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(nil, port, 0), .commonModes)
            CFRunLoopRun()
        }
        thread.name = "dev.swwm.tap"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    /// Returns nil to swallow the event. Tap thread.
    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> CGEvent? {
        if event.getIntegerValueField(.eventSourceUserData) == FocusPark.syntheticMark { return event }

        let s = state.read()

        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return event
        case .keyDown:
            noteInput(click: false)

            let combo = KeyCombo(keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
                                 modifiers: modifiers(event.flags))
            guard let command = s.bindings[combo] else {
                return event
            }

            DispatchQueue.main.async { [manager] in manager.run(command) }
            return nil
        case .mouseMoved:
            let p = event.location
            DispatchQueue.main.async { [self] in onMouseMoved(p) }
            hover(p, s)
            return event
        case .leftMouseDown, .rightMouseDown:
            noteInput(click: true)
            let p = event.location
            guard modifiers(event.flags) == s.settings.mouseModifier else {
                // A plain press may start a title-bar move or an edge resize.
                let clicks = Int(event.getIntegerValueField(.mouseEventClickState))
                press = type == .leftMouseDown ? s.window(at: p).flatMap { id in s.view.frames[id].map { (id, $0, p, clicks) } } : nil

                return event
            }

            guard let id = s.window(at: p), let frame = s.view.frames[id] else {
                return event
            }

            drag = Drag(
                window: id,
                resize: type == .rightMouseDown,
                floating: s.view.floating.contains(id),
                start: p,
                frame: frame
            )
            DispatchQueue.main.async { [manager] in manager.pointerFocus(id, hover: false) }
            return nil
        case .leftMouseDragged, .rightMouseDragged:
            guard let d = drag else {
                return event
            }

            // The app connection keeps only the newest of these writes.
            let p = event.location
            let dx = p.x - d.start.x, dy = p.y - d.start.y

            if !d.resize {
                DispatchQueue.main.async { [manager] in
                    manager.setPosition(d.window, CGPoint(x: d.frame.minX + dx, y: d.frame.minY + dy))
                }
            } else if d.floating {
                let r = CGRect(
                    x: d.frame.minX,
                    y: d.frame.minY,
                    width: max(100, d.frame.width + dx),
                    height: max(100, d.frame.height + dy)
                )
                DispatchQueue.main.async { [manager] in manager.setFrame(d.window, r) }
            }
            return nil
        case .leftMouseUp, .rightMouseUp:
            let p = event.location
            guard let d = drag else {
                if type == .leftMouseUp, let pr = press {
                    DispatchQueue.main.async { [self] in nativeDragEnded(
                        pr.window,
                        from: pr.frame,
                        pressedAt: pr.point,
                        clicks: pr.clicks,
                        at: p
                    ) }
                }
                press = nil
                return event
            }

            drag = nil
            DispatchQueue.main.async { [manager] in
                if d.resize {
                    manager.resized(d.window, by: CGSize(width: p.x - d.start.x, height: p.y - d.start.y))
                } else {
                    manager.dropped(d.window, at: p)
                }
            }
            return nil
        default:
            return event
        }
    }

    /// A click or key press: focus that follows it is the user's doing.
    private func noteInput(click: Bool) {
        let now = Date()
        DispatchQueue.main.async { [manager] in manager.noteInput(at: now, click: click) }
    }

    /// The window was moved by its title bar or resized by an edge without
    /// swwm: fold that into the layout instead of leaving it out of place.
    /// The frame comes fresh from the app: its last moved event may still be
    /// on the way. Main.
    private func nativeDragEnded(
        _ id: WindowID,
        from old: CGRect,
        pressedAt start: CGPoint,
        clicks: Int,
        at p: CGPoint
    ) {
        manager.readFrame(id) { [manager] new in
            guard let new else {
                return
            }
            switch nativeChange(
                from: old,
                to: new,
                pressedAt: start,
                clickCount: clicks
            ) {
            case .moved?: manager.dropped(id, at: p)
            case .resized(let delta)?: manager.resized(id, by: delta)
            case nil: break
            }
        }
    }

    private func modifiers(_ flags: CGEventFlags) -> Modifiers {
        var m: Modifiers = []

        if flags.contains(.maskShift) { m.insert(.shift) }
        if flags.contains(.maskControl) { m.insert(.ctrl) }
        if flags.contains(.maskAlternate) { m.insert(.alt) }
        if flags.contains(.maskCommand) { m.insert(.cmd) }

        return m
    }

    /// Focus follows mouse with autoraise. Throttled; paused right after
    /// swwm moved the cursor itself. No lookup while the cursor stays on the
    /// focused window and off the floating windows above it. Tap thread.
    private func hover(_ p: CGPoint, _ s: TapState) {
        guard s.settings.focusFollowsMouse, drag == nil else {
            return
        }

        let now = Date()
        guard now.timeIntervalSince(lastHover) > 0.03 else {
            return
        }
        lastHover = now

        if let f = s.view.focused, s.view.frames[f]?.contains(p) == true, !s.view.floatingFrames.contains(where: { $0.contains(p) }) { return }
        guard let id = s.window(at: p), hoverTakesFocus(
            id,
            focused: s.view.focused,
            shown: s.view.takesFocus,
            focusUnmanaged: s.view.focusUnmanaged,
            lastCursorMove: s.view.lastCursorMove,
            now: now
        ) else {
            return
        }

        DispatchQueue.main.async { [manager] in manager.pointerFocus(id, hover: true) }
    }
}

private func tapCallback(
    _ proxy: CGEventTapProxy,
    _ type: CGEventType,
    _ event: CGEvent,
    _ info: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let info else {
        return Unmanaged.passUnretained(event)
    }

    let tap = Unmanaged<EventTap>.fromOpaque(info).takeUnretainedValue()
    return tap.handle(type, event).map { Unmanaged.passUnretained($0) }
}

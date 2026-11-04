//
//  EventTap.swift
//  swwm
//
//  Created by Yesset Murat on 03.11.2026.
//

import AppKit
import SwwmCore

/// One session event tap for hotkeys (including cmd-tab), focus follows
/// mouse, and modifier+drag move/resize.
final class EventTap {

    private struct Drag {

        let window: WindowID
        let resize: Bool
        let start: CGPoint
        let frame: CGRect
    }

    private let manager: Manager
    private var bindings: [KeyCombo: Command] = [:]
    private var settings = Settings()
    private var port: CFMachPort?
    private var drag: Drag?
    private var press: (window: WindowID, frame: CGRect, point: CGPoint, clicks: Int)?  // plain left press on a managed window
    private var lastHover = Date.distantPast
    var onMouseMoved: (CGPoint) -> Void = { _ in }
    private var pendingDragPoint: CGPoint?  // coalesced: only the latest drag position is applied

    init(manager: Manager) {
        self.manager = manager
    }

    func update(config: Config) {
        bindings = config.bindings
        settings = config.settings
    }

    func start() {
        let types: [CGEventType] = [.keyDown, .mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp,
                                    .rightMouseDown, .rightMouseDragged, .rightMouseUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                 eventsOfInterest: mask, callback: tapCallback,
                                 userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let port else {
            NSLog("swwm: cannot create the event tap; is Accessibility granted?")
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, port, 0), .commonModes)
    }

    /// Returns nil to swallow the event.
    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> CGEvent? {
        if event.getIntegerValueField(.eventSourceUserData) == FocusPark.syntheticMark { return event }
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return event
        case .keyDown:
            manager.noteInput()
            let combo = KeyCombo(keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
                                 modifiers: modifiers(event.flags))
            guard let command = bindings[combo] else { return event }
            // The tap only decides; the work runs after it returns, so a slow
            // app never holds up system input.
            DispatchQueue.main.async { [manager] in manager.run(command) }
            return nil
        case .mouseMoved:
            let p = event.location
            DispatchQueue.main.async { [self] in onMouseMoved(p) }
            hover(p)
            return event
        case .leftMouseDown, .rightMouseDown:
            manager.noteInput()
            guard modifiers(event.flags) == settings.mouseModifier else {
                // A plain press may start a title-bar move or an edge resize.
                let p = event.location
                let clicks = Int(event.getIntegerValueField(.mouseEventClickState))
                DispatchQueue.main.async { [self] in
                    press = type == .leftMouseDown
                        ? manager.window(at: p).flatMap { id in manager.frame(of: id).map { (id, $0, p, clicks) } }
                        : nil
                }
                return event
            }
            guard let id = manager.window(at: event.location), let frame = manager.frame(of: id) else { return event }
            drag = Drag(window: id, resize: type == .rightMouseDown, start: event.location, frame: frame)
            DispatchQueue.main.async { [manager] in manager.focus(id, warp: false) }
            return nil
        case .leftMouseDragged, .rightMouseDragged:
            guard drag != nil else { return event }
            if pendingDragPoint == nil {
                DispatchQueue.main.async { [self] in applyDrag() }
            }
            pendingDragPoint = event.location
            return nil
        case .leftMouseUp, .rightMouseUp:
            let p = event.location
            guard let d = drag else {
                if type == .leftMouseUp {
                    DispatchQueue.main.async { [self] in
                        if let pr = press { nativeDragEnded(pr.window, from: pr.frame, pressedAt: pr.point, clicks: pr.clicks, at: p) }
                        press = nil
                    }
                }
                return event
            }
            drag = nil
            DispatchQueue.main.async { [self] in
                pendingDragPoint = nil
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

    private func applyDrag() {
        guard let d = drag, let p = pendingDragPoint else { return }
        pendingDragPoint = nil
        let dx = p.x - d.start.x, dy = p.y - d.start.y
        if !d.resize {
            manager.setPosition(d.window, CGPoint(x: d.frame.minX + dx, y: d.frame.minY + dy))
        } else if manager.isFloating(d.window) {
            manager.setFrame(d.window, CGRect(x: d.frame.minX, y: d.frame.minY,
                                              width: max(100, d.frame.width + dx), height: max(100, d.frame.height + dy)))
        }
    }

    /// The window was moved by its title bar or resized by an edge without
    /// swwm: fold that into the layout instead of leaving it out of place.
    private func nativeDragEnded(_ id: WindowID, from old: CGRect, pressedAt start: CGPoint, clicks: Int, at p: CGPoint) {
        guard let new = manager.frame(of: id) else { return }
        switch nativeChange(from: old, to: new, pressedAt: start, clickCount: clicks) {
        case .moved?: manager.dropped(id, at: p)
        case .resized(let delta)?: manager.resized(id, by: delta)
        case nil: break
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
    /// swwm moved the cursor itself.
    private func hover(_ p: CGPoint) {
        guard settings.focusFollowsMouse, drag == nil else { return }
        let now = Date()
        guard now.timeIntervalSince(lastHover) > 0.03, now.timeIntervalSince(manager.lastCursorMove) > 0.2 else { return }
        lastHover = now
        DispatchQueue.main.async { [manager] in
            if let id = manager.window(at: p), id != manager.focused, !manager.focusInUnmanagedWindow {
                manager.focus(id, warp: false)
            }
        }
    }
}

private func tapCallback(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent,
                         _ info: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let info else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<EventTap>.fromOpaque(info).takeUnretainedValue()
    return tap.handle(type, event).map { Unmanaged.passUnretained($0) }
}

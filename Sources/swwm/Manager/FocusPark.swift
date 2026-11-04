//
//  FocusPark.swift
//  swwm
//
//  Created by Yesset Murat on 03.11.2026.
//

import AppKit
import SwwmCore

/// Holds keyboard focus on a display with no windows, so macOS cannot hand
/// it to a window on another display.
final class FocusPark {

    private final class Panel: NSPanel {

        override var canBecomeKey: Bool { true }
    }

    private let panel: Panel = {
        let p = Panel(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.alphaValue = 0
        p.hasShadow = false
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        return p
    }()

    private(set) var monitor: MonitorID?

    /// Marks swwm's own clicks, which the event tap lets through untouched.
    static let syntheticMark: Int64 = 0x7377_776D  // "swwm"

    /// `desktopPoint`: a spot of the display's desktop with nothing on it; nil
    /// when there is none (or Finder draws no desktop), then swwm holds focus
    /// itself.
    func park(on m: MonitorInfo, desktopPoint p: CGPoint?) {
        monitor = m.id

        // An empty workspace is the desktop, Finder's, as the bar shows it:
        // click it, as the user would, so Finder is frontmost with the desktop
        // focused, not one of its windows, and the menu bar is Finder's. AX
        // cannot focus the desktop while a Finder window is key; a frontmost
        // swwm has no menu bar, and macOS would put some other app there.
        if let p {
            panel.orderOut(nil)
            for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                let e = CGEvent(
                    mouseEventSource: nil,
                    mouseType: type,
                    mouseCursorPosition: p,
                    mouseButton: .left
                )
                // No modifiers: the user may still hold the hotkey's alt, and an
                // option-click on the desktop hides the app that was active.
                e?.flags = []
                e?.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMark)
                e?.post(tap: .cghidEventTap)
            }
            return
        }

        let r = Displays.appKitRect(m.frame)
        panel.setFrameOrigin(NSPoint(x: r.midX, y: r.midY))

        // NSApp.activate() is cooperative and leaves the other app frontmost;
        // AXFrontmost makes the switch for real.
        let me = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        AXUIElementSetAttributeValue(me, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    func clear() {
        monitor = nil
        panel.orderOut(nil)
    }
}

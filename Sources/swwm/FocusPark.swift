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
        let p = Panel(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
                      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.alphaValue = 0
        p.hasShadow = false
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        return p
    }()

    private(set) var monitor: MonitorID?

    func park(on m: MonitorInfo) {
        monitor = m.id
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

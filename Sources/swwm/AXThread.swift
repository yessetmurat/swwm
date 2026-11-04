//
//  AXThread.swift
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

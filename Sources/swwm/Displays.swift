//
//  Displays.swift
//  swwm
//
//  Created by Yesset Murat on 03.11.2026.
//

import AppKit
import SwwmCore

enum Displays {

    /// Connected displays in global top-left coordinates (the AX space).
    static func current() -> [MonitorInfo] {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSScreen.screens.compactMap { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                return nil
            }
            let f = screen.frame
            return MonitorInfo(
                id: id, name: screen.localizedName, isBuiltin: CGDisplayIsBuiltin(id) != 0,
                frame: CGRect(x: f.minX, y: primaryHeight - f.maxY, width: f.width, height: f.height))
        }
    }

    /// Converts a top-left global rect to AppKit's bottom-left space.
    static func appKitRect(_ r: CGRect) -> NSRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    static var cursor: CGPoint { CGEvent(source: nil)?.location ?? .zero }
}

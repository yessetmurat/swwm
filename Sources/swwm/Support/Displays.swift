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
        NSScreen.screens.compactMap { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                return nil
            }

            return MonitorInfo(
                id: id,
                name: screen.localizedName,
                isBuiltin: CGDisplayIsBuiltin(id) != 0,
                frame: flipped(screen.frame)
            )
        }
    }

    /// A rect of one space in the other: top-left global (the AX space) and
    /// AppKit's bottom-left one mirror each other about the primary display.
    static func flipped(_ r: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(
            x: r.minX,
            y: primaryHeight - r.maxY,
            width: r.width,
            height: r.height
        )
    }

    static var cursor: CGPoint { CGEvent(source: nil)?.location ?? .zero }
}

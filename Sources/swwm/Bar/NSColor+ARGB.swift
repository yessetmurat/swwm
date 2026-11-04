//
//  NSColor+ARGB.swift
//  swwm
//
//  Created by Yesset Murat on 03.11.2026.
//

import AppKit
import SwwmCore

extension NSColor {

    convenience init(argb: UInt32) {
        self.init(
            srgbRed: CGFloat((argb >> 16) & 0xFF) / 255,
            green: CGFloat((argb >> 8) & 0xFF) / 255,
            blue: CGFloat(argb & 0xFF) / 255,
            alpha: CGFloat(argb >> 24) / 255
        )
    }
}

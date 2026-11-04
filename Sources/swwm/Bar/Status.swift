//
//  Status.swift
//  swwm
//
//  Created by Yesset Murat on 03.11.2026.
//

import AppKit
import SwwmCore

/// The right side of the bar: system state, the same on every display.
struct Status: Equatable {

    var language: String?
    var clock: String
    var battery: IndicatorItem?
    var volume: IndicatorItem?
}

//
//  Settings.swift
//  SwwmCore
//
//  Created by Yesset Murat on 03.11.2026.
//

import Foundation

public struct Settings: Equatable, Sendable {

    public var gap = 8.0
    public var padding = 8.0
    public var barHeight = 40.0
    public var focusFollowsMouse = true
    public var mouseFollowsFocus = true
    public var mouseModifier: Modifiers = .alt
    public var windowShadow: ShadowMode = .float
    public init() {}
}

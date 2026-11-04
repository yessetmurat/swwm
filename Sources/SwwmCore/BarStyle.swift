//
//  BarStyle.swift
//  SwwmCore
//
//  Created by Yesset Murat on 03.11.2026.
//

import Foundation
import TOMLKit

/// Bar look.
public struct BarStyle: Equatable, Sendable {

    public var background: UInt32 = 0x4000_0000  // ARGB
    public var itemBackground: UInt32 = 0x3300_0000
    public var foreground: UInt32 = 0xFFFF_FFFF
    public var workspaceFont = FontSpec(family: "IBM Plex Mono", style: "SemiBold", size: 15)
    public var labelFont = FontSpec(family: "IBM Plex Sans", style: "SemiBold", size: 14)

    public init() {}
}

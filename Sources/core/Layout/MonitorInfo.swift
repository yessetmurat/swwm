//
//  MonitorInfo.swift
//  SwwmCore
//
//  Created by Yesset Murat on 03.11.2026.
//

import CoreGraphics

public struct MonitorInfo: Equatable, Sendable {

    public var id: MonitorID
    public var name: String
    public var isBuiltin: Bool
    public var frame: CGRect  // global, top-left origin (AX coordinates)

    public init(
        id: MonitorID,
        name: String,
        isBuiltin: Bool,
        frame: CGRect
    ) {
        self.id = id
        self.name = name
        self.isBuiltin = isBuiltin
        self.frame = frame
    }
}

//
//  ServerWindow.swift
//  SwwmCore
//
//  Created by Yesset Murat on 04.11.2026.
//

import CoreGraphics

/// A window as the window server lists it. Bounds are global, top-left origin.
public struct ServerWindow: Equatable, Sendable {

    public let id: WindowID
    public let pid: Int32
    public let layer: Int
    public let bounds: CGRect
    public let alpha: Double
    public let owner: String

    public init(
        id: WindowID,
        pid: Int32,
        layer: Int,
        bounds: CGRect,
        alpha: Double,
        owner: String
    ) {
        self.id = id
        self.pid = pid
        self.layer = layer
        self.bounds = bounds
        self.alpha = alpha
        self.owner = owner
    }
}

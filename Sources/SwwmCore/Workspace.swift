//
//  Workspace.swift
//  SwwmCore
//
//  Created by Yesset Murat on 03.11.2026.
//

import CoreGraphics

public final class Workspace {

    public let name: String
    public let tree = DwindleTree()
    public var floating: [WindowID: CGRect] = [:]  // last frame of each floating window
    public var zoomed: WindowID?
    public internal(set) var mru: [WindowID] = []  // most recent first

    init(name: String) { self.name = name }

    public var windows: [WindowID] { tree.windows + floating.keys.sorted() }
}

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

    public init(id: WindowID, pid: Int32, layer: Int, bounds: CGRect, alpha: Double, owner: String) {
        self.id = id
        self.pid = pid
        self.layer = layer
        self.bounds = bounds
        self.alpha = alpha
        self.owner = owner
    }
}

/// A window-server notification (SkyLight's connection notify procs).
public enum WindowServerEvent: Equatable, Sendable {

    case added(WindowID)    // 1325: a window joined a space (opened, a sheet shown)
    case removed(WindowID)  // 1326: a window left its space (closed)
    case moved(WindowID)    // 806: only for windows asked for by id
    case resized(WindowID)  // 807: only for windows asked for by id

    public static let types: [UInt32] = [1325, 1326, 806, 807]

    /// 1325/1326 carry a u64 space id, then the u32 window id; 806/807 the
    /// window id alone.
    public init?(type: UInt32, data: [UInt8]) {
        func u32(at i: Int) -> UInt32? {
            guard data.count >= i + 4 else { return nil }
            return data[i..<i + 4].reversed().reduce(0) { $0 << 8 | UInt32($1) }
        }
        switch type {
        case 1325: guard let id = u32(at: 8) else { return nil }; self = .added(id)
        case 1326: guard let id = u32(at: 8) else { return nil }; self = .removed(id)
        case 806: guard let id = u32(at: 0) else { return nil }; self = .moved(id)
        case 807: guard let id = u32(at: 0) else { return nil }; self = .resized(id)
        default: return nil
        }
    }
}

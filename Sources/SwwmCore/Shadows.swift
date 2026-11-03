//
//  Shadows.swift
//  SwwmCore
//
//  Created by Yesset Murat on 03.11.2026.
//

/// `window-shadow`: `float` — only floating windows keep a shadow, `off` —
/// no window has one, `on` — swwm never touches shadows.
public enum ShadowMode: String, Sendable {

    case float, off, on
}

/// nil: leave the window's shadow alone.
public func shadowWanted(floating: Bool, mode: ShadowMode) -> Bool? {
    switch mode {
    case .float: floating
    case .off: false
    case .on: nil
    }
}

/// A request to the payload in Dock: little-endian int16 length of the rest,
/// opcode 0x01, uint32 window id, uint8 shadow.
public func shadowMessage(window: WindowID, shadow: Bool) -> [UInt8] {
    let id = window.littleEndian
    return [0x06, 0x00, 0x01]
        + withUnsafeBytes(of: id) { Array($0) }
        + [shadow ? 1 : 0]
}

/// Window levels swwm sets through the payload: floating windows stay above tiles.
public enum WindowLevel {

    public static let normal: Int32 = 0
    public static let floating: Int32 = 3  // kCGFloatingWindowLevel
}

/// A request to the payload in Dock: little-endian int16 length of the rest,
/// opcode 0x02, uint32 window id, int32 level.
public func levelMessage(window: WindowID, level: Int32) -> [UInt8] {
    let id = window.littleEndian, l = level.littleEndian
    return [0x09, 0x00, 0x02]
        + withUnsafeBytes(of: id) { Array($0) }
        + withUnsafeBytes(of: l) { Array($0) }
}

public enum DockSocket {

    /// In the user's temporary directory, shared by swwm and Dock (same user).
    public static let name = "swwm-dock.sock"
}

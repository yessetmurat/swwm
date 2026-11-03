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

public enum ShadowSocket {

    /// In the user's temporary directory, shared by swwm and Dock (same user).
    public static let name = "swwm-dock.sock"
}

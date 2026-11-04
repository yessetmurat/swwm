//
//  KeyCombo.swift
//  SwwmCore
//
//  Created by Yesset Murat on 03.11.2026.
//

public struct Modifiers: OptionSet, Hashable, Sendable {

    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let shift = Modifiers(rawValue: 1 << 0)
    public static let ctrl = Modifiers(rawValue: 1 << 1)
    public static let alt = Modifiers(rawValue: 1 << 2)
    public static let cmd = Modifiers(rawValue: 1 << 3)

    static let names: [String: Modifiers] = ["shift": .shift, "ctrl": .ctrl, "alt": .alt, "cmd": .cmd]
}

/// A hotkey such as `shift-alt-h`. Keys are physical U.S. ANSI positions, so a
/// binding works under any keyboard layout.
public struct KeyCombo: Hashable, Sendable {

    public var keyCode: UInt16  // macOS virtual key code (kVK_*)
    public var modifiers: Modifiers

    public init(keyCode: UInt16, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public static func parse(_ s: String) throws(CommandError) -> KeyCombo {
        let parts = s.lowercased().split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard let key = parts.last, let code = keyCodes[key] else {
            throw CommandError("unknown key in '\(s)'")
        }
        var mods: Modifiers = []
        for name in parts.dropLast() {
            guard let m = Modifiers.names[name], !mods.contains(m) else {
                throw CommandError("bad modifier '\(name)' in '\(s)'")
            }
            mods.insert(m)
        }
        return KeyCombo(keyCode: code, modifiers: mods)
    }

    static let keyCodes: [String: UInt16] = [
        "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05, "z": 0x06,
        "x": 0x07, "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E,
        "r": 0x0F, "y": 0x10, "t": 0x11, "o": 0x1F, "u": 0x20, "i": 0x22, "p": 0x23,
        "l": 0x25, "j": 0x26, "k": 0x28, "n": 0x2D, "m": 0x2E,
        "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "5": 0x17, "6": 0x16, "7": 0x1A,
        "8": 0x1C, "9": 0x19, "0": 0x1D,
        "equal": 0x18, "minus": 0x1B, "rightbracket": 0x1E, "leftbracket": 0x21,
        "quote": 0x27, "semicolon": 0x29, "backslash": 0x2A, "comma": 0x2B,
        "slash": 0x2C, "period": 0x2F, "grave": 0x32,
        "return": 0x24, "tab": 0x30, "space": 0x31, "delete": 0x33, "escape": 0x35,
        "left": 0x7B, "right": 0x7C, "down": 0x7D, "up": 0x7E,
    ]
}

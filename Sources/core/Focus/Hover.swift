//
//  Hover.swift
//  SwwmCore
//
//  Created by Yesset Murat on 04.11.2026.
//

import Foundation

/// Whether hovering window `id` gives it focus: it is managed and shown (a
/// window of a workspace just hidden may still be under the cursor), focus
/// is not in a window swwm does not manage (a system prompt, a sheet, a
/// launcher panel), and swwm did not move the cursor itself a moment ago.
public func hoverTakesFocus(
    _ id: WindowID,
    focused: WindowID?,
    shown: Set<WindowID>,
    focusUnmanaged: Bool,
    lastCursorMove: Date,
    now: Date
) -> Bool {
    id != focused && shown.contains(id) && !focusUnmanaged && now.timeIntervalSince(lastCursorMove) > 0.2
}

/// A focus or main-window change an app reports is a focus change only when
/// the app is frontmost: a background app may finish a stalled one later,
/// or switch its own tabs.
public func focusReportIsFocus(from pid: Int32, frontmost: Int32?) -> Bool { pid == frontmost }

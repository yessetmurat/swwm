//
//  FocusHistory.swift
//  SwwmCore
//
//  Created by Yesset Murat on 03.11.2026.
//

import Foundation

/// Recent focus changes. When a window closes, the app (or macOS) often moves
/// focus before the close event arrives; this keeps enough history to still
/// tell that the closed window had focus.
public struct FocusHistory {

    public private(set) var current: WindowID?
    private var previous: (id: WindowID, until: Date)?
    private var lastRemoval = Date.distantPast
    private var lastInput = Date.distantPast

    /// How long a window that lost focus still counts as focused.
    // Workaround: macOS activates a fallback app around a close (on cmd-q even
    // before the quit is reported) and posts no event saying it is done.
    public static let grace: TimeInterval = 0.3

    public init() {}

    public mutating func focused(_ id: WindowID?, at now: Date) {
        if let c = current, c != id { previous = (c, now) }
        current = id
    }

    public func wasRecentlyFocused(_ id: WindowID, now: Date) -> Bool {
        if current == id { return true }
        guard let p = previous, p.id == id else {
            return false
        }
        return now.timeIntervalSince(p.until) <= Self.grace
    }

    public mutating func removed(at now: Date) { lastRemoval = now }

    /// A click or a key press, the user's own doing.
    public mutating func input(at now: Date) { lastInput = now }

    /// Focus moving to a window on a hidden workspace shows that workspace
    /// when the user moved it: a click or key (Dock click, cmd-tab) within a
    /// second before. Not without one (macOS activating the last app when the
    /// hidden menu bar is revealed over an empty workspace), and not around a
    /// window going away: then it is macOS picking another app. On cmd-q the
    /// fallback app is activated before the quit app is reported gone, so a
    /// removal after the focus counts too: callers ask `grace` after the focus.
    public func autoShowAllowed(focusedAt: Date) -> Bool {
        let byUser = lastInput <= focusedAt && focusedAt.timeIntervalSince(lastInput) <= 1
        return byUser && lastRemoval < focusedAt.addingTimeInterval(-Self.grace)
    }
}

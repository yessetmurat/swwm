//
//  FocusEchoes.swift
//  SwwmCore
//
//  Created by Yesset Murat on 16.11.2026.
//

/// Focus reports that are no news. A focus command reaches its app later,
/// and the app answers it with reports of its own; when a newer command
/// follows before those arrive, they name a window focus has already left.
/// Until the newest command's window is reported, a report for the window
/// focus came from, or for an earlier command's window not reported yet, is
/// such an echo: it must neither move focus nor cancel the newer command.
public struct FocusEchoes: Sendable {

    public enum Report: Equatable, Sendable {

        case confirmed  // the newest command's window: the wait is over
        case echo       // a window focus has left: nothing new
        case news       // focus moved where no command sent it
    }

    private var target: WindowID?         // the newest command's window; nil for a park
    private var waiting = false           // the newest command is not answered yet
    private var left: Set<WindowID> = []  // windows focus has left since the last answer

    public init() {}

    /// Focus is sent to `target` (nil: to no window) while it is on `current`.
    public mutating func commanded(_ target: WindowID?, from current: WindowID?) {
        if waiting, let earlier = self.target { left.insert(earlier) }
        if let current { left.insert(current) }
        if let target { left.remove(target) }

        self.target = target
        waiting = true
    }

    /// What a report that `id` has focus means.
    public mutating func reported(_ id: WindowID) -> Report {
        guard waiting else {
            return .news
        }

        if id == target {
            movedOn()
            return .confirmed
        }
        if left.contains(id) { return .echo }

        movedOn()
        return .news
    }

    /// Focus moved where no command sent it: every report counts again.
    public mutating func movedOn() {
        target = nil
        waiting = false
        left = []
    }
}

//
//  FloatingLevels.swift
//  SwwmCore
//
//  Created by Yesset Murat on 04.11.2026.
//

/// A window-level change for the Dock module to apply.
public struct LevelChange: Equatable, Sendable {

    public let window: WindowID
    public let level: Int32

    public init(window: WindowID, level: Int32) {
        self.window = window
        self.level = level
    }
}

/// Which windows sit at the floating level: floating windows swwm manages,
/// and, while their app has one, the app's windows swwm does not manage
/// (sheets, dialogs, panels), which would open under them otherwise.
/// A window that leaves the screen may only be ordered out (Xcode's
/// Organizer): it comes back with the same ID, still at the floating level.
public struct FloatingLevels: Sendable {

    private var managed: [WindowID: Int32] = [:]   // raised managed windows, by app
    private var children: [WindowID: Int32] = [:]  // raised unmanaged windows, by app
    private var lowering: Set<WindowID> = []       // children lowered, until the Dock module has done it
    private var unanswered: [WindowID: Int] = [:]  // changes handed out and not answered yet
    private var departed: [WindowID: Int32] = [:]  // raised windows that left the screen, by app

    public init() {}

    public func isRaised(_ id: WindowID) -> Bool { managed[id] != nil || children[id] != nil }

    /// At the floating level by swwm's doing, not its app's: raised with its
    /// app's floating window, still there while swwm lowers it, or raised
    /// when it left the screen.
    public func isChild(_ id: WindowID) -> Bool {
        children[id] != nil || lowering.contains(id) || departed[id] != nil
    }

    /// A managed window floats or tiles; minimized or hidden counts as tiled.
    /// Nothing goes to one off the screen, it may be closed already: still
    /// raised, it floats as it is, or goes down when back (`appeared`).
    public mutating func set(_ id: WindowID, pid: Int32, floating: Bool) -> [LevelChange] {
        if departed[id] != nil {
            if floating {
                departed[id] = nil
                managed[id] = pid
            }
            return []
        }

        if floating {
            guard managed[id] == nil else {
                return []
            }
            managed[id] = pid
            return children.removeValue(forKey: id) == nil ? handOut([LevelChange(window: id, level: WindowLevel.floating)]) : []
        }

        guard managed.removeValue(forKey: id) != nil else {
            return []
        }
        return handOut([LevelChange(window: id, level: WindowLevel.normal)] + lowerChildren(of: pid))
    }

    /// A window reached the screen. One that left it raised: managed, it is
    /// raised for `set` to decide; else it stays up as a child while its app
    /// has a floating window, or goes down, to go up again if it is managed
    /// floating once its app reports it.
    public mutating func appeared(
        _ id: WindowID,
        pid: Int32,
        layer: Int,
        managed isManaged: Bool
    ) -> [LevelChange] {
        if departed.removeValue(forKey: id) != nil {
            guard !isManaged else {
                managed[id] = pid
                return []
            }

            guard !managed.values.contains(pid) else {
                children[id] = pid
                return []
            }

            lowering.insert(id)
            return handOut([LevelChange(window: id, level: WindowLevel.normal)])
        }

        guard layer == 0,
              !isManaged,
              !isRaised(id),
              managed.values.contains(pid) else {
            return []
        }
        children[id] = pid
        return handOut([LevelChange(window: id, level: WindowLevel.floating)])
    }

    /// A window left the screen: closed, or only ordered out. Its level
    /// stays until it comes back (`appeared`) or swwm quits (`removeAll`).
    public mutating func gone(_ id: WindowID) -> [LevelChange] {
        if let pid = managed[id] ?? children[id] { departed[id] = pid }

        children[id] = nil
        lowering.remove(id)
        unanswered[id] = nil
        guard let pid = managed.removeValue(forKey: id) else {
            return []
        }
        return handOut(lowerChildren(of: pid))
    }

    /// A raised child turned out to be a window swwm manages: `set` decides
    /// its level from now on.
    /// A child being lowered stays out of `managed`: its lowering is on the way.
    public mutating func adopt(_ id: WindowID, pid: Int32) {
        lowering.remove(id)
        guard children.removeValue(forKey: id) != nil || departed.removeValue(forKey: id) != nil else {
            return
        }
        managed[id] = pid
    }

    /// The Dock module applied the change: a lowered child is at the normal
    /// level now.
    public mutating func applied(_ change: LevelChange) {
        _ = answered(change)
        guard change.level == WindowLevel.normal else {
            return
        }
        lowering.remove(change.window)
    }

    /// The Dock module did not apply the change. A raise is forgotten, so the
    /// next change asks again; a lowered child is no child any more. Not a
    /// raise followed by a newer change for its window: that one decides.
    public mutating func failed(_ change: LevelChange) {
        let latest = answered(change)
        guard change.level == WindowLevel.floating else {
            lowering.remove(change.window)
            return
        }
        guard latest else {
            return
        }

        managed[change.window] = nil
        children[change.window] = nil
        departed[change.window] = nil
    }

    /// An app quit: its windows that left the screen are gone for good.
    public mutating func appQuit(_ pid: Int32) {
        departed = departed.filter { $0.value != pid }
    }

    /// Every raised window back to the normal level (quit).
    public mutating func removeAll() -> [LevelChange] {
        let all = Set(managed.keys).union(children.keys).union(departed.keys)
        managed = [:]
        children = [:]
        departed = [:]
        lowering = []
        unanswered = [:]

        return all.sorted().map { LevelChange(window: $0, level: WindowLevel.normal) }
    }

    /// Counts the changes the caller sends: each is answered once, in order.
    private mutating func handOut(_ changes: [LevelChange]) -> [LevelChange] {
        for c in changes { unanswered[c.window, default: 0] += 1 }
        return changes
    }

    /// True when no newer change for the window waits for its answer.
    private mutating func answered(_ change: LevelChange) -> Bool {
        let rest = (unanswered[change.window] ?? 1) - 1
        unanswered[change.window] = rest > 0 ? rest : nil
        return rest <= 0
    }

    private mutating func lowerChildren(of pid: Int32) -> [LevelChange] {
        guard !managed.values.contains(pid) else {
            return []
        }

        let gone = children.filter { $0.value == pid }.keys.sorted()
        for id in gone {
            children[id] = nil
            lowering.insert(id)
        }

        return gone.map { LevelChange(window: $0, level: WindowLevel.normal) }
    }
}

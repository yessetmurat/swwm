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
public struct FloatingLevels: Sendable {

    private var managed: [WindowID: Int32] = [:]   // raised managed windows, by app
    private var children: [WindowID: Int32] = [:]  // raised unmanaged windows, by app
    private var lowering: Set<WindowID> = []       // children lowered, until the Dock module has done it

    public init() {}

    public func isRaised(_ id: WindowID) -> Bool { managed[id] != nil || children[id] != nil }

    /// At the floating level by swwm's doing, not its app's: raised with its
    /// app's floating window, or still there while swwm lowers it.
    public func isChild(_ id: WindowID) -> Bool { children[id] != nil || lowering.contains(id) }

    /// A managed window floats or tiles; minimized or hidden counts as tiled.
    public mutating func set(_ id: WindowID, pid: Int32, floating: Bool) -> [LevelChange] {
        if floating {
            guard managed[id] == nil else {
                return []
            }
            managed[id] = pid
            return children.removeValue(forKey: id) == nil ? [LevelChange(window: id, level: WindowLevel.floating)] : []
        }

        guard managed.removeValue(forKey: id) != nil else {
            return []
        }
        return [LevelChange(window: id, level: WindowLevel.normal)] + lowerChildren(of: pid)
    }

    /// A window reached the screen.
    public mutating func appeared(
        _ id: WindowID,
        pid: Int32,
        layer: Int,
        managed isManaged: Bool
    ) -> [LevelChange] {
        guard layer == 0,
              !isManaged,
              !isRaised(id),
              managed.values.contains(pid) else {
            return []
        }
        children[id] = pid
        return [LevelChange(window: id, level: WindowLevel.floating)]
    }

    /// A window closed; its own level needs no change.
    public mutating func gone(_ id: WindowID) -> [LevelChange] {
        children[id] = nil
        lowering.remove(id)
        guard let pid = managed.removeValue(forKey: id) else {
            return []
        }
        return lowerChildren(of: pid)
    }

    /// A raised child turned out to be a window swwm manages: `set` decides
    /// its level from now on.
    /// A child being lowered stays out of `managed`: its lowering is on the way.
    public mutating func adopt(_ id: WindowID, pid: Int32) {
        lowering.remove(id)
        guard children.removeValue(forKey: id) != nil else {
            return
        }
        managed[id] = pid
    }

    /// The Dock module applied the change: a lowered child is at the normal
    /// level now.
    public mutating func applied(_ change: LevelChange) {
        guard change.level == WindowLevel.normal else {
            return
        }
        lowering.remove(change.window)
    }

    /// The Dock module did not apply the change. A raise is forgotten, so the
    /// next change asks again; a lowered child is no child any more.
    public mutating func failed(_ change: LevelChange) {
        guard change.level == WindowLevel.floating else {
            lowering.remove(change.window)
            return
        }
        managed[change.window] = nil
        children[change.window] = nil
    }

    /// Every raised window back to the normal level (quit).
    public mutating func removeAll() -> [LevelChange] {
        let all = Set(managed.keys).union(children.keys)
        managed = [:]
        children = [:]
        lowering = []

        return all.sorted().map { LevelChange(window: $0, level: WindowLevel.normal) }
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

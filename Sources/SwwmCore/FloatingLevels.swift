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

    public init() {}

    public func isRaised(_ id: WindowID) -> Bool { managed[id] != nil || children[id] != nil }

    public func isChild(_ id: WindowID) -> Bool { children[id] != nil }

    /// A managed window floats or tiles; minimized or hidden counts as tiled.
    public mutating func set(_ id: WindowID, pid: Int32, floating: Bool) -> [LevelChange] {
        if floating {
            guard managed[id] == nil else { return [] }
            managed[id] = pid
            return children.removeValue(forKey: id) == nil ? [LevelChange(window: id, level: WindowLevel.floating)] : []
        }
        guard managed.removeValue(forKey: id) != nil else { return [] }
        return [LevelChange(window: id, level: WindowLevel.normal)] + lowerChildren(of: pid)
    }

    /// A window reached the screen.
    public mutating func appeared(_ id: WindowID, pid: Int32, layer: Int, managed isManaged: Bool) -> [LevelChange] {
        guard layer == 0, !isManaged, !isRaised(id), managed.values.contains(pid) else { return [] }
        children[id] = pid
        return [LevelChange(window: id, level: WindowLevel.floating)]
    }

    /// A window closed; its own level needs no change.
    public mutating func gone(_ id: WindowID) -> [LevelChange] {
        children[id] = nil
        guard let pid = managed.removeValue(forKey: id) else { return [] }
        return lowerChildren(of: pid)
    }

    /// A raised child turned out to be a window swwm manages: `set` decides
    /// its level from now on.
    public mutating func adopt(_ id: WindowID, pid: Int32) {
        guard children.removeValue(forKey: id) != nil else { return }
        managed[id] = pid
    }

    /// The Dock module did not raise the window: forget it, so the next
    /// change asks again. A failed lowering changes nothing here.
    public mutating func failed(_ change: LevelChange) {
        guard change.level == WindowLevel.floating else { return }
        managed[change.window] = nil
        children[change.window] = nil
    }

    /// Every raised window back to the normal level (quit).
    public mutating func removeAll() -> [LevelChange] {
        let all = Set(managed.keys).union(children.keys)
        managed = [:]
        children = [:]
        return all.sorted().map { LevelChange(window: $0, level: WindowLevel.normal) }
    }

    private mutating func lowerChildren(of pid: Int32) -> [LevelChange] {
        guard !managed.values.contains(pid) else { return [] }
        let gone = children.filter { $0.value == pid }.keys.sorted()
        for id in gone { children[id] = nil }
        return gone.map { LevelChange(window: $0, level: WindowLevel.normal) }
    }
}

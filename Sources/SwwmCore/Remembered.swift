//
//  Remembered.swift
//  SwwmCore
//
//  Created by Yesset Murat on 04.11.2026.
//

/// Where minimized windows and windows of hidden apps belong, until they
/// come back or their app quits.
public struct Remembered: Sendable {

    public struct Entry: Equatable, Sendable {

        public let workspace: String
        public let pid: Int32
        public let floating: Bool

        public init(workspace: String, pid: Int32, floating: Bool) {
            self.workspace = workspace
            self.pid = pid
            self.floating = floating
        }
    }

    private var entries: [WindowID: Entry] = [:]

    public init() {}

    public mutating func remember(_ id: WindowID, _ e: Entry) { entries[id] = e }

    public mutating func take(_ id: WindowID) -> Entry? { entries.removeValue(forKey: id) }

    public mutating func forget(pid: Int32) { entries = entries.filter { $0.value.pid != pid } }

    public func contains(_ id: WindowID) -> Bool { entries[id] != nil }
}

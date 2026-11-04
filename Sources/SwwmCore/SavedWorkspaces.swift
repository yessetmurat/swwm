//
//  SavedWorkspaces.swift
//  SwwmCore
//
//  Created by Yesset Murat on 03.11.2026.
//

import Foundation

/// The workspace of each window, the tile layouts and the shown workspaces,
/// kept so a restarted swwm puts everything back. A window ID only counts
/// with the same process: IDs are reused after a reboot.
public struct SavedWorkspaces: Codable, Equatable, Sendable {

    struct Entry: Codable, Equatable, Sendable {

        var window: WindowID
        var pid: Int32
        var workspace: String
        var floating: Bool?  // optional: files from before this was kept
    }

    var entries: [Entry]
    var trees: [String: DwindleTree.Shape]?  // optional: files from before these were kept
    var active: [String]?

    public init(world: World, pids: [WindowID: Int32]) {
        entries = pids.compactMap { id, pid in
            world.workspace(containing: id).map { Entry(window: id, pid: pid, workspace: $0.name, floating: $0.floating[id] != nil) }
        }.sorted { $0.window < $1.window }
        var trees: [String: DwindleTree.Shape] = [:]
        for name in Set(entries.map(\.workspace)) {
            trees[name] = world.workspace(named: name)?.tree.shape
        }
        self.trees = trees
        active = world.monitors.compactMap { world.activeWorkspace(on: $0.id) }
    }

    public func workspace(of window: WindowID, pid: Int32) -> String? {
        entry(window, pid)?.workspace
    }

    public func wasFloating(_ window: WindowID, pid: Int32) -> Bool {
        entry(window, pid)?.floating == true
    }

    /// This state plus, from `old`, the entries of `pending` apps (running
    /// at start, not reported yet) and the tile shapes of the `untouched`
    /// workspaces: a restart during a slow start loses nothing.
    public func merging(_ old: SavedWorkspaces, pending: Set<Int32>, untouched: Set<String>) -> SavedWorkspaces {
        var merged = self
        let have = Set(entries.map(\.window))
        merged.entries += old.entries.filter { pending.contains($0.pid) && !have.contains($0.window) }
        merged.entries.sort { $0.window < $1.window }
        for name in untouched {
            guard let shape = old.trees?[name] else { continue }
            merged.trees = (merged.trees ?? [:]).merging([name: shape]) { _, old in old }
        }
        return merged
    }

    private func entry(_ window: WindowID, _ pid: Int32) -> Entry? {
        entries.first { $0.window == window && $0.pid == pid }
    }
}

extension World {

    /// Puts back the tile layouts and the shown workspaces of a saved run,
    /// once the windows are added.
    public func restore(_ saved: SavedWorkspaces) {
        for (name, shape) in saved.trees ?? [:] { workspace(named: name)?.tree.restore(shape) }
        for name in saved.active ?? [] where workspace(named: name) != nil { show(name) }
    }
}

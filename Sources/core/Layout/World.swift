//
//  World.swift
//  SwwmCore
//
//  Created by Yesset Murat on 03.11.2026.
//

import CoreGraphics

/// Workspaces, the displays they live on, and which one each display shows.
/// Pure state: the app layer applies it to real windows.
public final class World {

    public private(set) var config: Config
    public private(set) var monitors: [MonitorInfo] = []

    private var spaces: [String: Workspace] = [:]
    private var autoOwner: [String: String] = [:]   // auto workspace -> display name
    private var autoOrder: [String] = []
    private var home: [String: MonitorID] = [:]     // workspace -> display it is on now
    private var active: [MonitorID: String] = [:]   // kept for absent displays, restored on reconnect

    public init(config: Config) {
        self.config = config
        for name in config.allWorkspaces { spaces[name] = Workspace(name: name) }
    }

    private var order: [String] { config.allWorkspaces + autoOrder }

    // MARK: - Displays

    public func apply(config: Config) {
        let old = spaces
        self.config = config
        spaces = [:]
        for name in config.allWorkspaces { spaces[name] = old[name] ?? Workspace(name: name) }

        autoOrder.removeAll { name in
            // Now a config workspace.
            guard spaces[name] == nil else {
                return true
            }
            spaces[name] = old[name]
            return false
        }

        autoOwner = autoOwner.filter { autoOrder.contains($0.key) }
        let orphans = old.filter { spaces[$0.key] == nil }.values
        updateMonitors(monitors)

        // Windows of workspaces the new config dropped go to the home display's active workspace.
        if let target = homeMonitor.flatMap(activeWorkspace(on:)).flatMap(workspace(named:)) {
            for ws in orphans {
                for w in ws.windows {
                    if let f = ws.floating[w] { target.floating[w] = f } else { target.tree.insert(w, splitting: nil) }
                    target.mru.append(w)
                }
            }
        }
    }

    public func updateMonitors(_ ms: [MonitorInfo]) {
        monitors = ms
        var free = ms
        var owner: [Int: MonitorID] = [:]  // config monitor index -> display

        func take(_ i: Int, _ pick: (MonitorInfo) -> Bool) {
            guard let k = free.firstIndex(where: pick) else {
                return
            }
            owner[i] = free.remove(at: k).id
        }

        for (i, rule) in config.monitors.enumerated() where rule.match != "*" {
            if rule.match == "built-in" {
                take(i) { $0.isBuiltin }
            } else {
                take(i) { $0.name.caseInsensitiveCompare(rule.match) == .orderedSame }
            }
        }
        if let i = config.monitors.firstIndex(where: { $0.match == "*" }) { take(i) { _ in true } }

        // Displays nobody claimed get one workspace of their own.
        for m in free where !autoOwner.values.contains(m.name) {
            var name = m.name
            var n = 2
            while spaces[name] != nil {
                name = "\(m.name) \(n)"
                n += 1
            }
            spaces[name] = Workspace(name: name)
            autoOwner[name] = m.name
            autoOrder.append(name)
        }

        let fallback = homeMonitor
        home = [:]
        for (i, rule) in config.monitors.enumerated() {
            for name in rule.workspaces { home[name] = owner[i] ?? fallback }
        }
        for (name, displayName) in autoOwner {
            home[name] = free.first { $0.name == displayName }?.id ?? fallback
        }

        for m in ms {
            let list = workspaces(on: m.id)
            if let a = active[m.id], list.contains(a) { continue }
            active[m.id] = list.first
        }
    }

    /// Where workspaces of absent displays go: the built-in display, else the first.
    private var homeMonitor: MonitorID? { (monitors.first { $0.isBuiltin } ?? monitors.first)?.id }

    public func workspaces(on m: MonitorID) -> [String] { order.filter { home[$0] == m } }

    /// Every workspace, in config order.
    public var workspaceNames: [String] { order }

    public func activeWorkspace(on m: MonitorID) -> String? {
        guard monitors.contains(where: { $0.id == m }) else {
            return nil
        }
        return active[m]
    }

    public func monitor(of workspace: String) -> MonitorID? { home[workspace] }

    public func monitorInfo(_ m: MonitorID) -> MonitorInfo? { monitors.first { $0.id == m } }

    /// The display containing `p`; the home display when none does.
    public func monitor(at p: CGPoint) -> MonitorID? {
        monitors.first { $0.frame.contains(p) }?.id ?? homeMonitor
    }

    public func monitorNeighbor(of m: MonitorID, _ d: Direction) -> MonitorID? {
        neighbor(of: m, d, in: Dictionary(uniqueKeysWithValues: monitors.map { ($0.id, $0.frame) }))
    }

    public func workArea(of m: MonitorID) -> CGRect {
        guard let f = monitorInfo(m)?.frame else {
            return .zero
        }

        let s = config.settings
        return CGRect(
            x: f.minX + s.padding,
            y: f.minY + s.barHeight + s.padding,
            width: f.width - 2 * s.padding,
            height: f.height - s.barHeight - 2 * s.padding
        )
    }

    // MARK: - Workspaces and windows

    public func workspace(named name: String) -> Workspace? { spaces[name] }

    public func workspace(containing w: WindowID) -> Workspace? {
        spaces.values.first { $0.tree.contains(w) || $0.floating[w] != nil }
    }

    /// Where `w` is when its workspace is shown: its tile, the whole work
    /// area when zoomed, or its floating frame (centered when it would not
    /// show on its display).
    public func shownFrame(of w: WindowID) -> CGRect? {
        guard let ws = workspace(containing: w), let m = home[ws.name], let info = monitorInfo(m) else {
            return nil
        }

        let area = workArea(of: m)
        if let f = ws.floating[w] { return shownFloatingFrame(f, on: info, area: area) }
        return ws.zoomed == w ? area : ws.tree.frames(in: area, gap: config.settings.gap)[w]
    }

    /// True when `w`'s workspace is the one its display shows.
    public func isVisible(_ w: WindowID) -> Bool {
        guard let ws = workspace(containing: w), let m = home[ws.name] else {
            return false
        }
        return activeWorkspace(on: m) == ws.name
    }

    /// Makes `workspace` the one its display shows.
    public func show(_ workspace: String) {
        guard let m = home[workspace] else {
            return
        }
        active[m] = workspace
    }

    public func add(_ w: WindowID, to workspace: String, floatingFrame: CGRect?) {
        guard let ws = spaces[workspace], self.workspace(containing: w) == nil else {
            return
        }

        if let f = floatingFrame {
            ws.floating[w] = f
        } else {
            ws.tree.insert(w, splitting: ws.mru.first { ws.tree.contains($0) })
        }

        ws.mru.insert(w, at: 0)  // newest first, so unfocused additions still dwindle
    }

    /// Returns the display the window was on.
    @discardableResult
    public func remove(_ w: WindowID) -> MonitorID? {
        guard let ws = workspace(containing: w) else {
            return nil
        }

        ws.tree.remove(w)
        ws.floating[w] = nil
        ws.mru.removeAll { $0 == w }
        if ws.zoomed == w { ws.zoomed = nil }

        return home[ws.name]
    }

    /// Puts `new` where `old` is: same tile, floating frame, zoom and focus order.
    public func replace(_ old: WindowID, with new: WindowID) {
        guard let ws = workspace(containing: old) else {
            return
        }

        ws.tree.leaf(old)?.window = new
        if let f = ws.floating.removeValue(forKey: old) { ws.floating[new] = f }
        ws.mru = ws.mru.map { $0 == old ? new : $0 }
        if ws.zoomed == old { ws.zoomed = new }
    }

    public func move(_ w: WindowID, to workspace: String) {
        guard let from = self.workspace(containing: w), from.name != workspace else {
            return
        }

        let floating = from.floating[w]
        remove(w)
        add(w, to: workspace, floatingFrame: floating)
    }

    public func noteFocused(_ w: WindowID) {
        guard let ws = workspace(containing: w) else {
            return
        }

        ws.mru.removeAll { $0 == w }
        ws.mru.insert(w, at: 0)
    }

    /// The window to focus on display `m`: never one from another display.
    public func focusCandidate(on m: MonitorID) -> WindowID? {
        activeWorkspace(on: m).flatMap { spaces[$0]?.mru.first }
    }

    /// The next or previous workspace of display `m`, wrapping around.
    public func step(on m: MonitorID, forward: Bool) -> String? {
        let list = workspaces(on: m)
        guard !list.isEmpty else {
            return nil
        }

        let i = activeWorkspace(on: m).flatMap(list.firstIndex(of:)) ?? 0
        return list[(i + (forward ? 1 : list.count - 1)) % list.count]
    }
}

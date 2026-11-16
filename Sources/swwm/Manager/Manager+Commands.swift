//
//  Manager+Commands.swift
//  swwm
//
//  Created by Yesset Murat on 16.11.2026.
//

import AppKit
import SwwmCore

/// Commands from the bindings and requests from the CLI.
extension Manager {

    func run(_ command: Command) {
        switch command {
        case .focus(let d):
            if let n = neighborOfFocused(d, tiledOnly: false) { focus(n) }
        case .swap(let d):
            guard let f = focused, let ws = world.workspace(containing: f),
                  let n = neighborOfFocused(d, tiledOnly: true) else {
                return
            }

            touched.insert(ws.name)
            ws.tree.swap(f, n)
            relayout(f)
        case .warp(let d):
            guard let f = focused, let ws = world.workspace(containing: f),
                  let n = neighborOfFocused(d, tiledOnly: true) else {
                return
            }

            touched.insert(ws.name)
            ws.tree.warp(f, onto: n, from: opposite(d))
            relayout(f)
        case .focusMonitor(let d):
            if let m = focusedMonitor, let n = world.monitorNeighbor(of: m, d) { focus(monitor: n) }
        case .moveToMonitor(let d):
            guard let f = focused,
                  let m = focusedMonitor,
                  let n = world.monitorNeighbor(of: m, d),
                  let target = world.activeWorkspace(on: n) else {
                return
            }

            moveFocused(f, to: target)
        case .workspace(let name):
            show(name)
        case .moveToWorkspace(let name):
            if let f = focused { moveFocused(f, to: name) }
        case .workspaceNext, .workspacePrev:
            if let m = focusedMonitor, let name = world.step(on: m, forward: command == .workspaceNext) { show(name) }
        case .toggleFloat:
            toggleFloat()
        case .toggleZoom:
            guard let f = focused, let ws = world.workspace(containing: f), ws.tree.contains(f) else {
                return
            }

            ws.zoomed = ws.zoomed == f ? nil : f
            relayout(f)
        case .balance:
            guard let f = focused, let ws = world.workspace(containing: f) else {
                return
            }

            touched.insert(ws.name)
            ws.tree.balance()
            relayout(f)
        case .mirror(let axis):
            guard let f = focused, let ws = world.workspace(containing: f),
                  let m = world.monitor(of: ws.name) else {
                return
            }

            touched.insert(ws.name)
            ws.tree.mirror(axis, in: world.workArea(of: m))
            layout(m)
        case .exec(let line):
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = ["-c", line]
            try? p.run()
        case .reload:
            _ = onReload()
        case .quit:
            onQuit()
        }
    }

    /// Shows a workspace on its display and focuses that display.
    func show(_ name: String) {
        guard let m = world.monitor(of: name) else {
            return
        }

        if world.activeWorkspace(on: m) != name {
            world.show(name)
            layout(m)
        }

        focus(monitor: m)
    }

    private func moveFocused(_ id: WindowID, to name: String) {
        guard let from = world.workspace(containing: id), from.name != name,
              let fromMonitor = world.monitor(of: from.name) else {
            return
        }

        world.move(id, to: name)
        touched.formUnion([from.name, name])

        if let ws = world.workspace(named: name), let f = ws.floating[id],
           let m = world.monitor(of: name), m != fromMonitor {
            // A floating window keeps its size and lands centered on the new display.
            let area = world.workArea(of: m)
            ws.floating[id] = CGRect(
                x: area.midX - f.width / 2,
                y: area.midY - f.height / 2,
                width: f.width,
                height: f.height
            )
            windows[id]?.needsPlacement = true
        }

        layout(fromMonitor)

        guard let m = world.monitor(of: name) else {
            return
        }

        world.show(name)
        layout(m)
        focus(id)
    }

    private func toggleFloat() {
        guard let f = focused, let ws = world.workspace(containing: f), let m = world.monitor(of: ws.name) else {
            return
        }

        let wasFloating = ws.floating[f] != nil
        touched.insert(ws.name)
        world.remove(f)

        if wasFloating {
            world.add(f, to: ws.name, floatingFrame: nil)
        } else {
            let a = world.workArea(of: m)
            let frame = a.insetBy(dx: a.width / 4, dy: a.height / 4)
            world.add(f, to: ws.name, floatingFrame: frame)
            setFrame(f, frame)
            if let w = windows[f] { connections?.connection(w.pid)?.raise(f) }
        }

        layout(m)
        applyShadow(f)
        applyLevel(f)
        focus(f, warp: false)
    }

    private func relayout(_ id: WindowID) {
        if let ws = world.workspace(containing: id), let m = world.monitor(of: ws.name) { layout(m) }
    }

    private func neighborOfFocused(_ d: Direction, tiledOnly: Bool) -> WindowID? {
        guard let f = focused, let ws = world.workspace(containing: f), let m = world.monitor(of: ws.name) else {
            return nil
        }

        var frames = ws.tree.frames(in: world.workArea(of: m), gap: settings.gap)
        if !tiledOnly {
            for id in ws.floating.keys { frames[id] = windows[id]?.frame }
        } else if frames[f] == nil {
            return nil
        }

        return neighbor(of: f, d, in: frames)
    }

    private func opposite(_ d: Direction) -> Direction {
        switch d {
        case .left: .right
        case .right: .left
        case .up: .down
        case .down: .up
        }
    }

    // MARK: - CLI

    /// A CLI request. `quit` answers first and quits on the next turn, so the
    /// client still gets its reply.
    func handle(_ request: Request) -> Reply {
        switch request {
        case .query(.windows):
            return .ok(json(world.windowSnapshots(focused: focused, info: windowInfo)))
        case .query(.workspaces):
            return .ok(json(world.workspaceSnapshots()))
        case .query(.monitors):
            return .ok(json(world.monitorSnapshots(focusedMonitor: focusedMonitor)))
        case .command(.workspace(let name)) where world.workspace(named: name) == nil,
             .command(.moveToWorkspace(let name)) where world.workspace(named: name) == nil:
            return .error("unknown workspace '\(name)'")
        case .command(.quit):
            DispatchQueue.main.async { [self] in onQuit() }
            return .ok()
        case .command(.reload):
            return onReload().map { .error("config not applied: \($0)") } ?? .ok()
        case .command(let c):
            run(c)
            return .ok()
        }
    }

    /// From what swwm already knows: no AX round-trips, so a hung app cannot
    /// stall a query (and the event tap on the main thread).
    private func windowInfo(_ id: WindowID) -> WindowInfo? {
        windows[id].map {
            WindowInfo(app: $0.app, title: $0.title, frame: world.shownFrame(of: id) ?? .zero)
        }
    }
}

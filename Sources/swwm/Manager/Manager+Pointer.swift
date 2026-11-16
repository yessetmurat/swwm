//
//  Manager+Pointer.swift
//  swwm
//
//  Created by Yesset Murat on 16.11.2026.
//

import AppKit
import SwwmCore

/// What the event tap decides from, and where the drags it sees end.
extension Manager {

    /// Gives the event tap a fresh `TapView`, once per run-loop turn of
    /// changes.
    func publishSoon() {
        guard onPublish != nil, !publishPending else {
            return
        }

        publishPending = true
        DispatchQueue.main.async { [self] in
            publishPending = false

            let shown = Set(windows.values.filter { $0.hidden == nil && world.isVisible($0.id) }.map(\.id))
            let floating = Set(windows.keys.filter { world.workspace(containing: $0)?.floating[$0] != nil })
            let frames = windows.mapValues(\.frame)
            let floatingFrames = focused.flatMap(world.workspace(containing:)).map { Array($0.floating.values) } ?? []
            let raised = Set(windows.keys.filter(levels.isRaised))

            onPublish?(TapView(
                takesFocus: shown,
                raised: raised,
                floating: floating,
                frames: frames,
                floatingFrames: floatingFrames,
                focused: focused,
                focusUnmanaged: focusInUnmanagedWindow,
                lastCursorMove: lastCursorMove
            ))
        }
    }

    /// Ends a modifier+left drag: a tiled window dropped on another tiled
    /// window swaps with it, or joins the active workspace of the display it
    /// was dropped on.
    func dropped(_ id: WindowID, at p: CGPoint) {
        guard let ws = world.workspace(containing: id), let from = world.monitor(of: ws.name) else {
            return
        }

        if keepsFloatingFrame(id, in: ws) { return }

        touched.insert(ws.name)

        if let to = world.monitor(at: p), to != from, let target = world.activeWorkspace(on: to) {
            world.move(id, to: target)
            layout(from)
            layout(to)
            applyShadow(id)
            return
        }

        if let other = windowUnder(p, excluding: id), ws.tree.contains(other) {
            ws.tree.swap(id, other)
        }

        layout(from)
    }

    /// Ends a modifier+right drag on a tiled window.
    func resized(_ id: WindowID, by delta: CGSize) {
        guard let ws = world.workspace(containing: id), let m = world.monitor(of: ws.name) else {
            return
        }

        if keepsFloatingFrame(id, in: ws) { return }

        touched.insert(ws.name)
        ws.tree.resize(
            id,
            by: delta,
            in: world.workArea(of: m),
            gap: settings.gap
        )
        layout(m)
    }

    /// A floating window stays where the drag left it: its frame is read once
    /// more, now that the drag's writes are done (`learnFloatingFrame`).
    private func keepsFloatingFrame(_ id: WindowID, in ws: Workspace) -> Bool {
        guard ws.floating[id] != nil else {
            return false
        }

        readFrame(id) { _ in }
        return true
    }

    private func windowUnder(_ p: CGPoint, excluding id: WindowID) -> WindowID? {
        guard let ws = world.workspace(containing: id) else {
            return nil
        }

        return ws.tree.windows.first { $0 != id && world.shownFrame(of: $0)?.contains(p) == true }
    }
}

//
//  Bar.swift
//  SwwmCore
//
//  Created by Yesset Murat on 03.11.2026.
//

import CoreGraphics
import Foundation

/// What one display's bar shows on the left.
public struct BarState: Equatable, Sendable {

    public struct Workspace: Equatable, Sendable {

        public var name: String   // as in config, used for clicks
        public var label: String  // name.uppercased()
        public var active: Bool
    }

    public var workspaces: [Workspace]
    public var app: String
}

extension World {

    /// The app shown is the focused window's when it is on this display's
    /// active workspace, else that workspace's most recent window's, else
    /// Finder (the desktop).
    public func barState(on m: MonitorID, focused: WindowID?, appName: (WindowID) -> String?) -> BarState {
        let active = activeWorkspace(on: m)
        let list = workspaces(on: m).map {
            BarState.Workspace(name: $0, label: $0.uppercased(), active: $0 == active)
        }
        let ws = active.flatMap(workspace(named:))
        let shown = focused.flatMap { f in ws?.windows.contains(f) == true ? f : nil } ?? ws?.mru.first
        return BarState(workspaces: list, app: shown.flatMap(appName) ?? "Finder")
    }
}

/// The bar steps aside for the auto-hidden macOS menu bar: it hides when the
/// cursor touches the display's top edge (where macOS reveals the menu) and
/// comes back once the cursor leaves the bar's area.
public func barHidden(cursor p: CGPoint, display f: CGRect, barHeight: CGFloat, hidden: Bool) -> Bool {
    guard p.x >= f.minX, p.x < f.maxX, p.y >= f.minY, p.y < f.maxY else { return false }
    if p.y <= f.minY + 1 { return true }
    return hidden && p.y < f.minY + barHeight
}

/// Before fading back in, the bar waits while the macOS menu bar is still
/// fully in place: up to 0.5 s normally, as long as a dropdown menu is open.
public func waitForMenu(menuInPlace: Bool, dropdownOpen: Bool, waited: TimeInterval) -> Bool {
    menuInPlace && (dropdownOpen || waited < 0.5)
}

//
//  Tracking.swift
//  SwwmCore
//
//  Created by Yesset Murat on 04.11.2026.
//

import CoreGraphics

public enum TrackDecision: Equatable, Sendable {

    case skip                                     // dialogs, sheets, fullscreen, minimized, overlays
    case takeOver(WindowID)                       // a native tab: it takes the tile of the tab it covers
    case manage(workspace: String, floating: Bool)
}

public struct TrackContext: Sendable {

    public var appTiles: [WindowID: CGRect]  // shown frames of the app's managed windows
    public var isChild: Bool                 // raised by swwm with its app's floating window
    public var adopting: Bool                // the app was running when swwm started
    public var appHidden: Bool               // cmd-H: its windows come back when the app unhides
    public var point: CGPoint                // window centre when adopting, else the cursor

    public init(
        appTiles: [WindowID: CGRect],
        isChild: Bool,
        adopting: Bool,
        appHidden: Bool,
        point: CGPoint
    ) {
        self.appTiles = appTiles
        self.isChild = isChild
        self.adopting = adopting
        self.appHidden = appHidden
        self.point = point
    }
}

/// Whether swwm manages a window and where: its remembered workspace (one a
/// reload dropped does not count), the last run's, its rule's, else the
/// active one of the display at the point. A new or newly shown native tab
/// takes the tile of the tab it covers, which drops out of the app's list. No
/// tab bar check: when a tab closes, the next one is reported before the
/// close, already alone. Takes the window from `remembered` only when it is
/// managed.
public func trackDecision(
    _ s: AppWindow,
    world: World,
    context c: TrackContext,
    remembered: inout Remembered,
    saved: SavedWorkspaces?
) -> TrackDecision {
    // A floating window a crashed run left at the floating level is swwm's, not an app's panel.
    let raisedLastRun = s.layer == Int(WindowLevel.floating) && saved?.wasFloating(s.id, pid: s.pid) == true

    guard !c.appHidden,
          s.isStandard,
          s.layer == 0 || c.isChild || (c.adopting && raisedLastRun),
          !s.isFullScreen,
          !s.isMinimized else {
        return .skip
    }

    if let old = tabSibling(of: s.frame, among: c.appTiles.filter { !s.listed.contains($0.key) }) { return .takeOver(old) }

    let rule = world.config.rules.first { $0.matches(app: s.app, title: s.title) }
    let back = remembered.take(s.id)
    let floating = rule?.float == true || !s.isResizable || back?.floating == true
        || (c.adopting && saved?.wasFloating(s.id, pid: s.pid) == true)

    guard let target = back.flatMap({ world.workspace(named: $0.workspace)?.name })
        ?? saved?.workspace(of: s.id, pid: s.pid).flatMap({ world.workspace(named: $0)?.name })
        ?? rule?.workspace
        ?? world.monitor(at: c.point).flatMap(world.activeWorkspace(on:)) else {
        if let back { remembered.remember(s.id, back) }
        return .skip
    }

    return .manage(workspace: target, floating: floating)
}

//
//  Park.swift
//  SwwmCore
//
//  Created by Yesset Murat on 04.11.2026.
//

import CoreGraphics

/// Where swwm clicks Finder's desktop to park focus on an empty workspace,
/// best first: under the cursor when it is on that display's work area, and
/// mid work area when mouse-follows-focus puts the cursor there. A click
/// moves the cursor, so with mouse-follows-focus off only the cursor's own
/// spot is used.
public func parkPoints(cursor: CGPoint, area: CGRect, mouseFollowsFocus: Bool) -> [CGPoint] {
    let mid = CGPoint(x: area.midX, y: area.midY)
    return (area.contains(cursor) ? [cursor] : []) + (mouseFollowsFocus ? [mid] : [])
}

public enum ParkStep: Equatable, Sendable {

    case click                // Finder's desktop is on top at the point
    case wait(Set<WindowID>)  // only these windows, which swwm is moving away, are above it
    case noClick              // something else is above it, or there is no desktop
}

/// What is at `p` decides: `onScreen` front to back. Windows with alpha 0
/// and the cursor (listed as a window when it sits on the point) take no
/// click and do not count.
public func parkStep(
    at p: CGPoint,
    onScreen: [ServerWindow],
    leaving: Set<WindowID>,
    desktopLayer: Int
) -> ParkStep {
    let cursor = Int(CGWindowLevelForKey(.cursorWindow))
    var above: Set<WindowID> = []

    for w in onScreen where w.alpha > 0 && w.layer != cursor && w.bounds.contains(p) {
        if w.layer == desktopLayer && w.owner == "Finder" { return above.isEmpty ? .click : .wait(above) }
        guard leaving.contains(w.id) else {
            return .noClick
        }
        above.insert(w.id)
    }

    return .noClick
}

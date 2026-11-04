//
//  Pointer.swift
//  SwwmCore
//
//  Created by Yesset Murat on 04.11.2026.
//

import CoreGraphics

/// The window at `p` that may take focus: the topmost visible window there,
/// when it is at layer 0, or at the floating level and `raised` by swwm. Nil
/// when swwm's own window (the bar) or any other window (a menu, a popover,
/// the Dock) is on top. Transparent windows and the cursor take no clicks
/// and are looked through.
public func windowUnder(
    _ p: CGPoint,
    in onScreen: [ServerWindow],
    ownPID: Int32,
    raised: (WindowID) -> Bool
) -> WindowID? {
    let cursor = Int(CGWindowLevelForKey(.cursorWindow))
    guard let top = onScreen.first(where: { $0.alpha > 0 && $0.layer != cursor && $0.bounds.contains(p) }),
          top.pid != ownPID else {
        return nil
    }
    return top.layer == 0 || (top.layer == Int(WindowLevel.floating) && raised(top.id)) ? top.id : nil
}

public enum NativeChange: Equatable, Sendable {

    case moved
    case resized(CGSize)  // how far the edge that moved went
}

/// Whether `p` is in the window's title bar: the top 30pt of `frame`.
public func inTitleBar(_ p: CGPoint, of frame: CGRect) -> Bool { frame.contains(p) && p.y - frame.minY <= 30 }

/// A title-bar move or an edge resize the user made without swwm, from the
/// window's frame at the press and after it. Nil for no change, a double
/// click (zoom), or a press elsewhere (a button that resizes its window).
public func nativeChange(
    from old: CGRect,
    to new: CGRect,
    pressedAt p: CGPoint,
    clickCount: Int
) -> NativeChange? {
    guard new != old, clickCount == 1 else {
        return nil
    }

    let titleBand = inTitleBar(p, of: old)
    let onEdge = old.insetBy(dx: -6, dy: -6).contains(p) && !old.insetBy(dx: 6, dy: 6).contains(p)
    if new.size == old.size { return titleBand ? .moved : nil }
    guard onEdge else {
        return nil
    }

    // The edge that moved: right/bottom if it did, else left/top.
    let dx = new.maxX != old.maxX ? new.maxX - old.maxX : new.minX - old.minX
    let dy = new.maxY != old.maxY ? new.maxY - old.maxY : new.minY - old.minY

    return .resized(CGSize(width: dx, height: dy))
}

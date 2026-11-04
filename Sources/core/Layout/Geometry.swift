//
//  Geometry.swift
//  SwwmCore
//
//  Created by Yesset Murat on 04.11.2026.
//

import CoreGraphics

/// Equal up to `tolerance` on every edge: apps round (632.5 comes back as
/// 633), and some size in steps.
public func near(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 1) -> Bool {
    abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
        && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
}

/// Native tabs are windows of their own sharing one frame: the tab of
/// `candidates` that `frame` belongs with has that frame. A window that
/// only overlaps it (Windows App's session window replacing its smaller
/// connecting window) is no tab.
public func tabSibling(of frame: CGRect, among candidates: [WindowID: CGRect]) -> WindowID? {
    candidates.filter { near($0.value, frame) }.keys.min()
}

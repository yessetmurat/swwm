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
/// `candidates` that `frame` belongs with is the one it overlaps most, when
/// that overlap is at least half of the smaller of the two.
public func tabSibling(of frame: CGRect, among candidates: [WindowID: CGRect]) -> WindowID? {
    func area(_ r: CGRect) -> CGFloat { r.isNull ? 0 : r.width * r.height }
    let best = candidates.map { (id: $0.key, overlap: area($0.value.intersection(frame)), other: $0.value) }
        .max { ($0.overlap, $1.id) < ($1.overlap, $0.id) }
    guard let best, best.overlap > 0, best.overlap >= min(area(frame), area(best.other)) / 2 else { return nil }
    return best.id
}

//
//  Neighbor.swift
//  SwwmCore
//
//  Created by Yesset Murat on 03.11.2026.
//

import CoreGraphics

/// The rect nearest to `w` on side `d` that overlaps it on the other axis.
/// Ties go to the larger overlap, then to the one aligned closest to `w`.
public func neighbor(of w: WindowID, _ d: Direction, in frames: [WindowID: CGRect]) -> WindowID? {
    guard let me = frames[w] else {
        return nil
    }
    let tolerance: CGFloat = 1
    let horizontal = d == .left || d == .right

    func distance(_ c: CGRect) -> CGFloat? {
        let gap: CGFloat
        switch d {
        case .right: gap = c.minX - me.maxX
        case .left: gap = me.minX - c.maxX
        case .down: gap = c.minY - me.maxY
        case .up: gap = me.minY - c.maxY
        }
        return gap >= -tolerance ? gap : nil
    }
    func overlap(_ c: CGRect) -> CGFloat {
        horizontal ? min(me.maxY, c.maxY) - max(me.minY, c.minY)
                   : min(me.maxX, c.maxX) - max(me.minX, c.minX)
    }
    func misalignment(_ c: CGRect) -> CGFloat {
        horizontal ? abs(c.minY - me.minY) : abs(c.minX - me.minX)
    }

    return frames
        .filter { $0.key != w && overlap($0.value) > 0 && distance($0.value) != nil }
        .min { a, b in
            let (da, db) = (distance(a.value)!, distance(b.value)!)
            if da != db { return da < db }
            let (oa, ob) = (overlap(a.value), overlap(b.value))
            if oa != ob { return oa > ob }
            return misalignment(a.value) < misalignment(b.value)
        }?.key
}

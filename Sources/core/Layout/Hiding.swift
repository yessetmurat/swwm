//
//  Hiding.swift
//  SwwmCore
//
//  Created by Yesset Murat on 03.11.2026.
//

import CoreGraphics

/// Where to move a window of an inactive workspace: off a bottom corner of
/// its display, 1pt still inside. macOS pulls such a window back up until
/// ~66pt show above the bottom, so the window may end up anywhere in the
/// display's height; the corner is chosen on the side where that whole band
/// touches no other display.
public func hiddenOrigin(for size: CGSize, on m: MonitorInfo, others: [MonitorInfo]) -> CGPoint {
    let f = m.frame
    let candidates = [
        CGPoint(x: f.maxX - 1, y: f.maxY - 1),               // bottom-right
        CGPoint(x: f.minX - size.width + 1, y: f.maxY - 1),  // bottom-left
    ]

    func spill(_ p: CGPoint) -> CGFloat {
        let band = CGRect(
            x: p.x,
            y: f.minY,
            width: size.width,
            height: f.height
        )
        return others.reduce(0) { sum, o in
            let i = band.intersection(o.frame)
            return sum + (i.isNull ? 0 : i.width * i.height)
        }
    }

    return candidates.min { spill($0) < spill($1) }!
}

/// Where a floating window goes when its workspace is shown: its saved frame
/// if at least half of it is on `m`, else centered in `area`. A frame saved
/// at the hiding spot (a sliver) or on another display is never kept.
public func shownFloatingFrame(_ r: CGRect, on m: MonitorInfo, area: CGRect) -> CGRect {
    let i = r.intersection(m.frame)
    if !i.isNull, i.width * i.height >= r.width * r.height / 2 { return r }
    return CGRect(
        x: area.midX - r.width / 2,
        y: area.midY - r.height / 2,
        width: r.width,
        height: r.height
    )
}

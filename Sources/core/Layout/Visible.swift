//
//  Visible.swift
//  SwwmCore
//
//  Created by Yesset Murat on 03.11.2026.
//

import CoreGraphics

/// Where to put the cursor on `rect` so it is not over any of `covers`
/// (floating windows above a tile): the centre when free, else the free
/// point nearest to it on a 9×9 grid of cell centres; nil when all are covered.
public func visiblePoint(of rect: CGRect, under covers: [CGRect]) -> CGPoint? {
    let centre = CGPoint(x: rect.midX, y: rect.midY)
    func free(_ p: CGPoint) -> Bool { !covers.contains { $0.contains(p) } }
    if free(centre) { return centre }

    let n = 9
    var points: [CGPoint] = []
    for i in 0..<n {
        for j in 0..<n {
            points.append(CGPoint(x: rect.minX + rect.width * (CGFloat(i) + 0.5) / CGFloat(n),
                                  y: rect.minY + rect.height * (CGFloat(j) + 0.5) / CGFloat(n)))
        }
    }

    return points.filter(free).min { hypot($0.x - centre.x, $0.y - centre.y) < hypot($1.x - centre.x, $1.y - centre.y) }
}

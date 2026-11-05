//
//  TileFit.swift
//  SwwmCore
//
//  Created by Yesset Murat on 05.11.2026.
//

import CoreGraphics

/// How a window's size sits in its tile.
public enum TileFit: Equatable, Sendable {

    case fits       // up to the slack: some windows size in steps
    case overflows  // larger one way: it would cover its neighbors
    case short      // smaller, and larger no way: it covers nothing
}

/// How a window of size `w` sits in a tile of size `t`.
public func tileFit(window w: CGSize, tile t: CGSize, slack: CGFloat = 20) -> TileFit {
    if w.width > t.width + slack || w.height > t.height + slack { return .overflows }

    return w.width < t.width - slack || w.height < t.height - slack ? .short : .fits
}

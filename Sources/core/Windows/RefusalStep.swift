//
//  RefusalStep.swift
//  SwwmCore
//
//  Created by Yesset Murat on 16.11.2026.
//

import CoreGraphics

/// What the size check of a new tiled window comes to.
public enum RefusalStep: Equatable, Sendable {

    case settled                   // in its tile (or no tile to check any more): the check is over
    case whenShown                 // its workspace is hidden: checked once it is shown
    case waitAgain                 // its tile changed since the check was asked for: the full wait again
    case tileAgain(after: Double)  // smaller, or no answer: its tile is written again, then checked again
    case float                     // larger than its tile: it would cover its neighbors
}

/// One size check. `tiled`: the window is still a plain tile (not floated,
/// zoomed or gone); `tile`: its tile's size now, nil while its workspace is
/// hidden; `asked`: that size when the check was asked for (nil: not known,
/// judge at once); `window`: the size its app reports, nil for no answer.
/// A smaller window is asked again after each of `waits`, then left as it is.
public func refusalStep(
    tiled: Bool,
    tile: CGSize?,
    asked: CGSize?,
    window: CGSize?,
    attempt: Int,
    waits: [Double]
) -> RefusalStep {
    guard tiled else {
        return .settled
    }

    guard let tile else {
        return .whenShown
    }

    if let asked, asked != tile { return .waitAgain }

    let again: RefusalStep = attempt < waits.count ? .tileAgain(after: waits[attempt]) : .settled
    guard let window else {
        return again
    }

    switch tileFit(window: window, tile: tile) {
    case .fits: return .settled
    case .overflows: return .float
    case .short: return again
    }
}

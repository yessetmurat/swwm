//
//  RefusalStepTests.swift
//  SwwmCoreTests
//
//  Created by Yesset Murat on 16.11.2026.
//

import CoreGraphics
import Testing
@testable import SwwmCore

private let tile = CGSize(width: 800, height: 600)
private let waits = [0.2, 0.3]

private func step(
    tiled: Bool = true,
    tile t: CGSize? = tile,
    asked: CGSize? = tile,
    window: CGSize? = tile,
    attempt: Int = 0
) -> RefusalStep {
    refusalStep(
        tiled: tiled,
        tile: t,
        asked: asked,
        window: window,
        attempt: attempt,
        waits: waits
    )
}

@Test func windowInItsTileIsSettled() {
    #expect(step() == .settled)
}

@Test func windowNoLongerTiledIsSettled() {
    #expect(step(tiled: false, window: CGSize(width: 2000, height: 2000)) == .settled)
}

@Test func hiddenWorkspaceIsCheckedWhenShown() {
    #expect(step(tile: nil) == .whenShown)
}

@Test func changedTileWaitsAgain() {
    // Asked for the old, wider tile: the window still has that size, and has had no time for the new one.
    let old = CGSize(width: 1600, height: 600)

    #expect(step(asked: old, window: old) == .waitAgain)
}

@Test func checkWithoutAskedTileJudgesAtOnce() {
    #expect(step(asked: nil, window: CGSize(width: 1600, height: 600)) == .float)
}

@Test func largerWindowFloats() {
    #expect(step(window: CGSize(width: 900, height: 600)) == .float)
}

@Test func smallerWindowIsTiledAgainUntilTheWaitsRunOut() {
    let small = CGSize(width: 500, height: 600)

    #expect(step(window: small, attempt: 0) == .tileAgain(after: 0.2))
    #expect(step(window: small, attempt: 1) == .tileAgain(after: 0.3))
    #expect(step(window: small, attempt: 2) == .settled)
}

@Test func unansweredReadIsTiledAgain() {
    #expect(step(window: nil) == .tileAgain(after: 0.2))
    #expect(step(window: nil, attempt: 2) == .settled)
}

//
//  TileFitTests.swift
//  SwwmCoreTests
//
//  Created by Yesset Murat on 05.11.2026.
//

import CoreGraphics
import Testing
@testable import SwwmCore

@Test func aWindowInStepsFitsItsTile() {
    let fit = tileFit(window: CGSize(width: 2530, height: 1370), tile: CGSize(width: 2544, height: 1384))

    #expect(fit == .fits)
}

@Test func aWindowSmallerBothWaysFallsShort() {
    let fit = tileFit(window: CGSize(width: 1292, height: 1125), tile: CGSize(width: 2544, height: 1384))

    #expect(fit == .short)
}

@Test func aWindowShortOneWayFallsShort() {
    let fit = tileFit(window: CGSize(width: 2040, height: 1116), tile: CGSize(width: 2040, height: 1273))

    #expect(fit == .short)
}

@Test func aWindowWiderThanItsTileOverflows() {
    let fit = tileFit(window: CGSize(width: 736, height: 633), tile: CGSize(width: 504, height: 632.5))

    #expect(fit == .overflows)
}

@Test func aWindowLargerOneWayOverflowsWhileShortTheOther() {
    let fit = tileFit(window: CGSize(width: 800, height: 300), tile: CGSize(width: 504, height: 632.5))

    #expect(fit == .overflows)
}

//
//  PlacementTests.swift
//  SwwmCoreTests
//
//  Created by Yesset Murat on 03.11.2026.
//

import CoreGraphics
import Testing
@testable import SwwmCore

private let area = CGRect(x: 8, y: 48, width: 1496, height: 926)

@Test func visibleFloatingFrameIsKept() {
    let r = CGRect(x: 100, y: 100, width: 400, height: 300)

    #expect(shownFloatingFrame(r, on: B, area: area) == r)
}

@Test func sliverAtHidingSpotIsCentered() {
    // A frame captured while hidden: 1pt inside the display corner.
    let r = CGRect(
        x: B.frame.maxX - 1,
        y: B.frame.maxY - 66,
        width: 400,
        height: 300
    )
    #expect(shownFloatingFrame(r, on: B, area: area) == CGRect(
        x: area.midX - 200,
        y: area.midY - 150,
        width: 400,
        height: 300
    ))
}

@Test func frameOnAnotherDisplayIsCentered() {
    let r = CGRect(x: 2000, y: 100, width: 400, height: 300)

    #expect(shownFloatingFrame(r, on: B, area: area).midX == area.midX)
}

//
//  HiderTests.swift
//  SwwmCoreTests
//
//  Created by Yesset Murat on 03.11.2026.
//

import CoreGraphics
import Testing
@testable import SwwmCore

private let size = CGSize(width: 2040, height: 1273)
// The external display sits higher and ends 51pt above the laptop's bottom.
private let laptop = MonitorInfo(id: 1, name: "L", isBuiltin: true, frame: CGRect(x: 0, y: 0, width: 2056, height: 1329))
private let external = MonitorInfo(id: 2, name: "X", isBuiltin: false, frame: CGRect(x: 2056, y: -162, width: 2560, height: 1440))

@Test func hidesAwayFromNeighborOnTheRight() {
    // macOS keeps ~66pt of a window above the display bottom, so a window
    // hidden toward a display on the right would show on it.
    let p = hiddenOrigin(for: size, on: laptop, others: [external])
    #expect(p == CGPoint(x: laptop.frame.minX - size.width + 1, y: laptop.frame.maxY - 1))
}

@Test func hidesAwayFromNeighborOnTheLeft() {
    let p = hiddenOrigin(for: size, on: external, others: [laptop])
    #expect(p == CGPoint(x: external.frame.maxX - 1, y: external.frame.maxY - 1))
}

@Test func hidesBottomRightWhenAlone() {
    #expect(hiddenOrigin(for: size, on: B, others: []) == CGPoint(x: B.frame.maxX - 1, y: B.frame.maxY - 1))
}

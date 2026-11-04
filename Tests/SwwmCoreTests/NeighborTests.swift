//
//  NeighborTests.swift
//  SwwmCoreTests
//
//  Created by Yesset Murat on 03.11.2026.
//

import CoreGraphics
import Testing
@testable import SwwmCore

@Test func neighbors() {
    let f = tree3().frames(in: R, gap: 0)

    #expect(neighbor(of: 1, .right, in: f) == 2)  // 2 and 3 tie on overlap; 2's top is closer
    #expect(neighbor(of: 3, .up, in: f) == 2)
    #expect(neighbor(of: 2, .down, in: f) == 3)
    #expect(neighbor(of: 2, .left, in: f) == 1)
    #expect(neighbor(of: 3, .left, in: f) == 1)
    #expect(neighbor(of: 1, .left, in: f) == nil)
    #expect(neighbor(of: 2, .up, in: f) == nil)
}

@Test func neighborWithGap() {
    let f = tree3().frames(in: R, gap: 8)

    #expect(neighbor(of: 1, .right, in: f) == 2)
    #expect(neighbor(of: 3, .up, in: f) == 2)
}

@Test func neighborNearestWins() {
    let f: [WindowID: CGRect] = [
        1: CGRect(x: 0, y: 0, width: 100, height: 100),
        2: CGRect(x: 300, y: 0, width: 100, height: 100),
        3: CGRect(x: 150, y: 50, width: 100, height: 100),
    ]

    #expect(neighbor(of: 1, .right, in: f) == 3)
}

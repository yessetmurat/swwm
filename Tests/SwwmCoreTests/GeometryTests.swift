//
//  GeometryTests.swift
//  SwwmCoreTests
//
//  Created by Yesset Murat on 04.11.2026.
//

import CoreGraphics
import Testing
@testable import SwwmCore

@Test func nearAllowsAppRounding() {
    #expect(near(CGRect(x: 0, y: 0, width: 632.5, height: 10), CGRect(x: 0, y: 0, width: 633, height: 10)))
}

@Test func nearRespectsTolerance() {
    let a = CGRect(x: 0, y: 0, width: 100, height: 100), b = CGRect(x: 0, y: 0, width: 110, height: 100)

    #expect(!near(a, b))
    #expect(near(a, b, tolerance: 20))
}

@Test func tabSiblingPicksLargestOverlap() {
    let f = CGRect(x: 0, y: 0, width: 100, height: 100)

    #expect(tabSibling(of: f, among: [1: CGRect(x: 50, y: 0, width: 100, height: 100),
                                      2: CGRect(x: 2, y: 0, width: 100, height: 100)]) == 2)
}

@Test func tabSiblingNeedsHalfOverlap() {
    #expect(tabSibling(of: CGRect(x: 0, y: 0, width: 100, height: 100),
                       among: [1: CGRect(x: 90, y: 0, width: 100, height: 100)]) == nil)
}

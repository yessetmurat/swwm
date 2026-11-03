//
//  VisibleTests.swift
//  SwwmCoreTests
//
//  Created by Yesset Murat on 03.11.2026.
//

import CoreGraphics
import Testing
@testable import SwwmCore

private let r = CGRect(x: 0, y: 0, width: 900, height: 900)

@Test func visiblePointIsCentreWhenFree() {
    #expect(visiblePoint(of: r, under: []) == CGPoint(x: 450, y: 450))
    #expect(visiblePoint(of: r, under: [CGRect(x: 600, y: 600, width: 100, height: 100)]) == CGPoint(x: 450, y: 450))
}

@Test func visiblePointAvoidsCover() {
    let p = visiblePoint(of: r, under: [CGRect(x: 200, y: 0, width: 700, height: 900)])!
    #expect(r.contains(p) && p.x < 200)
}

@Test func visiblePointNilWhenCovered() {
    #expect(visiblePoint(of: r, under: [r.insetBy(dx: -10, dy: -10)]) == nil)
}

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

@Test func tabSiblingNeedsTheSameFrame() {
    let f = CGRect(x: 0, y: 0, width: 100, height: 100)
    let candidates: [WindowID: CGRect] = [
        1: CGRect(x: 2, y: 0, width: 100, height: 100),
        2: f,
    ]

    #expect(tabSibling(of: f, among: candidates) == 2)
}

@Test func tabSiblingToleratesRounding() {
    let f = CGRect(x: 1032, y: 48, width: 1016, height: 632.5)
    let candidates: [WindowID: CGRect] = [7: CGRect(x: 1032, y: 48, width: 1016, height: 633)]

    #expect(tabSibling(of: f, among: candidates) == 7)
}

@Test func tabSiblingIgnoresAWindowItOverlaps() {
    // Windows App swaps its connecting window for a bigger session window.
    let connecting = CGRect(x: 3061, y: 446, width: 550, height: 192)
    let session = CGRect(x: 2520, y: 100, width: 1626, height: 887)

    #expect(tabSibling(of: session, among: [5490: connecting]) == nil)
    #expect(tabSibling(of: connecting, among: [5493: session]) == nil)
}

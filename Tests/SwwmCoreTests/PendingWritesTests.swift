//
//  PendingWritesTests.swift
//  SwwmCoreTests
//
//  Created by Yesset Murat on 04.11.2026.
//

import CoreGraphics
import Testing
@testable import SwwmCore

private let a = CGRect(x: 0, y: 0, width: 10, height: 10)
private let b = CGRect(x: 5, y: 5, width: 20, height: 20)

@Test func newerWriteReplacesOlder() {
    let w = PendingWrites<CGRect>()
    #expect(w.put(1, a))   // the first one needs a run
    #expect(!w.put(1, b))  // the run that is queued takes the newer one
    #expect(w.take(1) == b)
    #expect(w.take(1) == nil)
}

@Test func writesToForgottenWindowAreDropped() {
    let w = PendingWrites<CGRect>()
    _ = w.put(1, a)
    w.forget(1)
    #expect(w.take(1) == nil)
}

@Test func windowsDoNotShareWrites() {
    let w = PendingWrites<CGRect>()
    _ = w.put(1, a)
    #expect(w.put(2, b))
    #expect(w.take(1) == a)
    #expect(w.take(2) == b)
}

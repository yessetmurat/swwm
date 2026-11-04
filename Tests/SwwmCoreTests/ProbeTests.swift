//
//  ProbeTests.swift
//  SwwmCoreTests
//
//  Created by Yesset Murat on 04.11.2026.
//

import Testing
@testable import SwwmCore

private let waits = [0.03, 0.06, 0.1, 0.15]

@Test func oneAxisFloats() {
    #expect(probeStep(
        width: true,
        height: false,
        attempt: 0,
        waits: waits
    ) == .float)
    #expect(probeStep(
        width: false,
        height: true,
        attempt: 2,
        waits: waits
    ) == .float)
}

@Test func noAxisAsksAgain() {
    let first = probeStep(
        width: false,
        height: false,
        attempt: 0,
        waits: waits
    )
    let second = probeStep(
        width: false,
        height: false,
        attempt: 1,
        waits: waits
    )

    guard case .askAgain(let a) = first, case .askAgain(let b) = second else {
        Issue.record("expected askAgain")
        return
    }

    #expect(abs(a - 0.03) < 1e-9)
    #expect(abs(b - 0.03) < 1e-9)
}

@Test func noAxisAfterLastWaitTiles() {
    #expect(probeStep(
        width: false,
        height: false,
        attempt: 4,
        waits: waits
    ) == .tile(learned: nil))
}

@Test func bothAxesTileAndLearn() {
    #expect(probeStep(
        width: true,
        height: true,
        attempt: 0,
        waits: waits
    ) == .tile(learned: true))
}

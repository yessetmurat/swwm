//
//  FloatingLevelsTests.swift
//  SwwmCoreTests
//
//  Created by Yesset Murat on 04.11.2026.
//

import Testing
@testable import SwwmCore

// pid 10: the app with the floating window; pid 11: another app.
private func up(_ id: WindowID) -> LevelChange { LevelChange(window: id, level: WindowLevel.floating) }
private func down(_ id: WindowID) -> LevelChange { LevelChange(window: id, level: WindowLevel.normal) }

private func withChild() -> FloatingLevels {
    var l = FloatingLevels()
    _ = l.set(1, pid: 10, floating: true)
    _ = l.appeared(
        2,
        pid: 10,
        layer: 0,
        managed: false
    )
    return l
}

@Test func floatingWindowGoesUpOnce() {
    var l = FloatingLevels()

    #expect(l.set(1, pid: 10, floating: true) == [up(1)])
    #expect(l.set(1, pid: 10, floating: true) == [])
    #expect(l.isRaised(1))
}

@Test func childOfRaisedAppGoesUp() {
    var l = FloatingLevels()
    _ = l.set(1, pid: 10, floating: true)

    #expect(l.appeared(
        2,
        pid: 10,
        layer: 0,
        managed: false
    ) == [up(2)])
    #expect(l.isChild(2))
    #expect(l.appeared(
        2,
        pid: 10,
        layer: 0,
        managed: false
    ) == [])
}

@Test func otherAppsManagedAndHighWindowsStay() {
    var l = FloatingLevels()
    _ = l.set(1, pid: 10, floating: true)

    #expect(l.appeared(
        3,
        pid: 11,
        layer: 0,
        managed: false
    ) == [])
    #expect(l.appeared(
        4,
        pid: 10,
        layer: 0,
        managed: true
    ) == [])
    #expect(l.appeared(
        5,
        pid: 10,
        layer: 101,
        managed: false
    ) == [])
}

@Test func lastRaisedWindowLowersChildren() {
    var l = withChild()

    #expect(l.set(1, pid: 10, floating: false) == [down(1), down(2)])
    #expect(!l.isRaised(2))
}

@Test func otherRaisedWindowKeepsChildren() {
    var l = withChild()
    _ = l.set(3, pid: 10, floating: true)

    #expect(l.set(1, pid: 10, floating: false) == [down(1)])
    #expect(l.isChild(2))
}

@Test func closedParentLowersChildren() {
    var l = withChild()

    #expect(l.gone(1) == [down(2)])
    #expect(!l.isRaised(1))
}

@Test func closedChildIsForgotten() {
    var l = withChild()

    #expect(l.gone(2) == [])
    #expect(l.set(1, pid: 10, floating: false) == [down(1)])
}

@Test func adoptedChildIsLoweredWhenTiled() {
    var l = withChild()
    l.adopt(2, pid: 10)

    #expect(!l.isChild(2))
    #expect(l.isRaised(2))
    #expect(l.set(2, pid: 10, floating: false) == [down(2)])
}

@Test func loweredChildStaysChildUntilApplied() {
    var l = withChild()
    let changes = l.gone(1)

    // The window server still shows it raised until the Dock module answers.
    #expect(l.isChild(2))

    l.applied(changes[0])

    #expect(!l.isChild(2))
}

@Test func failedLoweringForgetsChild() {
    var l = withChild()
    let changes = l.gone(1)
    l.failed(changes[0])

    #expect(!l.isChild(2))
}

@Test func adoptedLoweringChildStaysLowWhenTiled() {
    var l = withChild()
    _ = l.gone(1)
    l.adopt(2, pid: 10)

    #expect(!l.isChild(2))
    #expect(l.set(2, pid: 10, floating: false) == [])
}

@Test func adoptedLoweringChildGoesUpWhenFloating() {
    var l = withChild()
    _ = l.gone(1)
    l.adopt(2, pid: 10)

    #expect(l.set(2, pid: 10, floating: true) == [up(2)])
}

@Test func failedChangeIsAskedAgain() {
    var l = FloatingLevels()
    let changes = l.set(1, pid: 10, floating: true)
    l.failed(changes[0])

    #expect(!l.isRaised(1))
    #expect(l.set(1, pid: 10, floating: true) == changes)
}

@Test func removeAllLowersEverything() {
    var l = withChild()

    #expect(l.removeAll() == [down(1), down(2)])
    #expect(!l.isRaised(1) && !l.isRaised(2))
}

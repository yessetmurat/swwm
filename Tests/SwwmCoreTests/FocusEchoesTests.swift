//
//  FocusEchoesTests.swift
//  SwwmCoreTests
//
//  Created by Yesset Murat on 16.11.2026.
//

import Testing
@testable import SwwmCore

@Test func reportWithoutCommandIsNews() {
    var e = FocusEchoes()

    #expect(e.reported(1) == .news)
}

@Test func sourceWindowIsEchoUntilConfirmed() {
    var e = FocusEchoes()
    e.commanded(2, from: 1)

    #expect(e.reported(1) == .echo)
    #expect(e.reported(1) == .echo)  // an app answers one command more than once
    #expect(e.reported(2) == .confirmed)
    #expect(e.reported(1) == .news)
}

@Test func earlierUnconfirmedTargetIsEcho() {
    var e = FocusEchoes()
    e.commanded(2, from: 1)
    e.commanded(3, from: 2)
    e.commanded(4, from: 3)

    #expect(e.reported(2) == .echo)
    #expect(e.reported(3) == .echo)
    #expect(e.reported(4) == .confirmed)
}

@Test func otherWindowIsNewsAndEndsTheWait() {
    var e = FocusEchoes()
    e.commanded(2, from: 1)

    #expect(e.reported(9) == .news)
    #expect(e.reported(1) == .news)
}

@Test func parkLeavesSourceAsEcho() {
    var e = FocusEchoes()
    e.commanded(nil, from: 1)

    #expect(e.reported(1) == .echo)
    #expect(e.reported(9) == .news)
}

@Test func movedOnForgets() {
    var e = FocusEchoes()
    e.commanded(2, from: 1)
    e.movedOn()

    #expect(e.reported(1) == .news)
}

@Test func targetIsNeverItsOwnEcho() {
    var e = FocusEchoes()
    e.commanded(2, from: 1)
    e.commanded(1, from: 2)  // back to where it came from

    #expect(e.reported(2) == .echo)
    #expect(e.reported(1) == .confirmed)
}

@Test func finishedParkCountsReportsAgain() {
    var e = FocusEchoes()
    e.commanded(nil, from: 1)  // no window to report: only `movedOn` ends this wait

    #expect(e.reported(1) == .echo)
    e.movedOn()

    #expect(e.reported(1) == .news)
}

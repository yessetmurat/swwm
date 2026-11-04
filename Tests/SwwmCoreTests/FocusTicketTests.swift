//
//  FocusTicketTests.swift
//  SwwmCoreTests
//
//  Created by Yesset Murat on 04.11.2026.
//

import Testing
@testable import SwwmCore

@Test func staleFocusIsDropped() {
    let t = FocusTicket()
    let a = t.next()
    let b = t.next()

    #expect(a != b)
    #expect(t.current == b)  // a focus sent with `a` is stale by the time it runs
}

@Test func staleTicketStopsBetweenSteps() {
    // The app takes the main-window step after a long stall; meanwhile the
    // user focused something else: no raise, no activation.
    let t = FocusTicket()
    let mine = t.next()
    var ran: [Int] = []
    t.run(mine, [{ ran.append(1); _ = t.next() }, { ran.append(2) }, { ran.append(3) }])

    #expect(ran == [1])
}

@Test func currentTicketRunsAllSteps() {
    let t = FocusTicket()
    var ran: [Int] = []
    t.run(t.next(), [{ ran.append(1) }, { ran.append(2) }])

    #expect(ran == [1, 2])
}

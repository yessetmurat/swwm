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

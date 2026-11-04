//
//  RememberedTests.swift
//  SwwmCoreTests
//
//  Created by Yesset Murat on 04.11.2026.
//

import Testing
@testable import SwwmCore

@Test func takeConsumesEntry() {
    var r = Remembered()
    let e = Remembered.Entry(workspace: "2", pid: 10, floating: true)
    r.remember(1, e)
    #expect(r.contains(1))
    #expect(r.take(1) == e)
    #expect(r.take(1) == nil)
}

@Test func forgetDropsAppEntries() {
    var r = Remembered()
    r.remember(1, .init(workspace: "1", pid: 10, floating: false))
    r.remember(2, .init(workspace: "1", pid: 10, floating: false))
    r.remember(3, .init(workspace: "1", pid: 11, floating: false))
    r.forget(pid: 10)
    #expect(!r.contains(1) && !r.contains(2))
    #expect(r.contains(3))
}

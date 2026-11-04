//
//  WindowServerEventTests.swift
//  SwwmCoreTests
//
//  Created by Yesset Murat on 04.11.2026.
//

import Testing
@testable import SwwmCore

@Test func addedCarriesWindowAfterSpaceID() {
    #expect(WindowServerEvent(type: 1325, data: [1, 0, 0, 0, 0, 0, 0, 0, 0xfb, 0x09, 0, 0]) == .added(2555))
}

@Test func removedHasTheAddedLayout() {
    #expect(WindowServerEvent(type: 1326, data: [1, 0, 0, 0, 0, 0, 0, 0, 0xfa, 0x09, 0, 0]) == .removed(2554))
}

@Test func movedAndResizedCarryWindowFirst() {
    #expect(WindowServerEvent(type: 806, data: [0xfd, 0x09, 0, 0]) == .moved(2557))
    #expect(WindowServerEvent(type: 807, data: [0xfd, 0x09, 0, 0]) == .resized(2557))
}

@Test func shortOrUnknownIsNil() {
    #expect(WindowServerEvent(type: 1325, data: [0xfd, 0x09, 0, 0]) == nil)
    #expect(WindowServerEvent(type: 125, data: [1, 0, 0, 0, 0, 0, 0, 0]) == nil)
}

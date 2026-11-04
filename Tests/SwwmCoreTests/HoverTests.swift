//
//  HoverTests.swift
//  SwwmCoreTests
//
//  Created by Yesset Murat on 04.11.2026.
//

import Foundation
import Testing
@testable import SwwmCore

private let now = Date(timeIntervalSinceReferenceDate: 1000)
private let long = now.addingTimeInterval(-1)

@Test func shownWindowTakesHoverFocus() {
    #expect(hoverTakesFocus(
        2,
        focused: 1,
        shown: [1, 2],
        focusUnmanaged: false,
        lastCursorMove: long,
        now: now
    ))
}

@Test func justHiddenWindowTakesNoHoverFocus() {
    // Its workspace was hidden a moment ago; its frame may still be under the cursor.
    #expect(!hoverTakesFocus(
        2,
        focused: 1,
        shown: [1],
        focusUnmanaged: false,
        lastCursorMove: long,
        now: now
    ))
}

@Test func hoverWaitsAfterSwwmMovedTheCursor() {
    #expect(!hoverTakesFocus(
        2,
        focused: 1,
        shown: [1, 2],
        focusUnmanaged: false,
        lastCursorMove: now.addingTimeInterval(-0.1),
        now: now
    ))
}

@Test func hoverLeavesUnmanagedFocusAlone() {
    #expect(!hoverTakesFocus(
        2,
        focused: nil,
        shown: [2],
        focusUnmanaged: true,
        lastCursorMove: long,
        now: now
    ))
}

@Test func hoverOnFocusedWindowDoesNothing() {
    #expect(!hoverTakesFocus(
        2,
        focused: 2,
        shown: [2],
        focusUnmanaged: false,
        lastCursorMove: long,
        now: now
    ))
}

@Test func onlyTheFrontmostAppReportsFocus() {
    // A background app that finishes a stalled main-window change reports it.
    #expect(focusReportIsFocus(from: 10, frontmost: 10))
    #expect(!focusReportIsFocus(from: 11, frontmost: 10))
    #expect(!focusReportIsFocus(from: 11, frontmost: nil))
}

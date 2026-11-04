//
//  FocusHistoryTests.swift
//  SwwmCoreTests
//
//  Created by Yesset Murat on 03.11.2026.
//

import Foundation
import Testing
@testable import SwwmCore

private let t0 = Date(timeIntervalSinceReferenceDate: 1000)

@Test func currentIsRecentlyFocused() {
    var h = FocusHistory()
    h.focused(1, at: t0)
    #expect(h.current == 1)
    #expect(h.wasRecentlyFocused(1, now: t0.addingTimeInterval(5)))
}

@Test func focusTakenByClosingAppStillCounts() {
    // The closing app focuses its other window before the close event arrives.
    var h = FocusHistory()
    h.focused(1, at: t0)
    h.focused(2, at: t0.addingTimeInterval(0.05))
    #expect(h.wasRecentlyFocused(1, now: t0.addingTimeInterval(0.1)))
    #expect(!h.wasRecentlyFocused(1, now: t0.addingTimeInterval(1)))
    #expect(!h.wasRecentlyFocused(3, now: t0.addingTimeInterval(0.1)))
}

@Test func autoShowPausedRightAfterRemoval() {
    var h = FocusHistory()
    h.input(at: t0.addingTimeInterval(-0.1))
    #expect(h.autoShowAllowed(focusedAt: t0))
    h.removed(at: t0)
    #expect(!h.autoShowAllowed(focusedAt: t0.addingTimeInterval(0.1)))
    h.input(at: t0.addingTimeInterval(0.9))
    #expect(h.autoShowAllowed(focusedAt: t0.addingTimeInterval(1)))
}

/// On cmd-q macOS activates the next app before it reports the quit one gone.
@Test func autoShowCancelledByRemovalRightAfterFocus() {
    var h = FocusHistory()
    h.input(at: t0.addingTimeInterval(-0.1))
    h.removed(at: t0.addingTimeInterval(0.03))
    #expect(!h.autoShowAllowed(focusedAt: t0))
}

/// Revealing the hidden menu bar over an empty workspace makes macOS
/// activate the last regular app: no click or key went before it.
@Test func autoShowNeedsInputJustBefore() {
    var h = FocusHistory()
    #expect(!h.autoShowAllowed(focusedAt: t0))
    h.input(at: t0.addingTimeInterval(-0.3))  // Dock click, cmd-tab
    #expect(h.autoShowAllowed(focusedAt: t0))
    #expect(!h.autoShowAllowed(focusedAt: t0.addingTimeInterval(2)))
}

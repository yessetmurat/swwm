//
//  BarTests.swift
//  SwwmCoreTests
//
//  Created by Yesset Murat on 03.11.2026.
//

import CoreGraphics
import Testing
@testable import SwwmCore

@Test func barShowsDisplayWorkspaces() {
    let w = world([B, E])
    w.show("w")
    let s = w.barState(on: 2, focused: nil) { _ in nil }
    #expect(s.workspaces.map(\.label) == ["Q", "W", "E", "R"])
    #expect(s.workspaces.map(\.active) == [false, true, false, false])
    #expect(s.workspaces[1].name == "w")
}

@Test func oneDisplayBarHasAllWorkspaces() {
    #expect(world([B]).barState(on: 1, focused: nil) { _ in nil }.workspaces.count == 8)
}

@Test func barAppIsFocusedWindowOnThisDisplay() {
    let w = world([B, E])
    w.add(1, to: "1", floatingFrame: nil)
    w.add(10, to: "q", floatingFrame: nil)
    w.add(11, to: "q", floatingFrame: nil)
    let names: [WindowID: String] = [1: "Ghostty", 10: "Firefox", 11: "Xcode"]
    w.noteFocused(11)
    w.noteFocused(10)
    #expect(w.barState(on: 2, focused: 10) { names[$0] }.app == "Firefox")
    #expect(w.barState(on: 2, focused: 1) { names[$0] }.app == "Firefox")  // focus elsewhere: MRU head
    #expect(w.barState(on: 1, focused: 10) { names[$0] }.app == "Ghostty")
}

@Test func emptyWorkspaceShowsFinder() {
    #expect(world([B, E]).barState(on: 2, focused: nil) { _ in nil }.app == "Finder")
}

@Test func barStepsAsideForTheMenuBar() {
    let f = B.frame  // top at y 0, bar 40 tall
    // Cursor at the very top edge: macOS reveals its menu there, the bar hides.
    #expect(barHidden(cursor: CGPoint(x: 100, y: 0), display: f, barHeight: 40, hidden: false))
    // Still within the bar area: the menu stays out, so the bar stays hidden.
    #expect(barHidden(cursor: CGPoint(x: 100, y: 20), display: f, barHeight: 40, hidden: true))
    // Below the bar: back.
    #expect(!barHidden(cursor: CGPoint(x: 100, y: 60), display: f, barHeight: 40, hidden: true))
    // Clicking inside a visible bar keeps it visible.
    #expect(!barHidden(cursor: CGPoint(x: 100, y: 20), display: f, barHeight: 40, hidden: false))
    // Cursor on another display: shown.
    #expect(!barHidden(cursor: CGPoint(x: 3000, y: 0), display: f, barHeight: 40, hidden: true))
}

@Test func barWaitsWhileAMenuIsOpen() {
    // The menu bar still fully in place: wait, but not forever.
    #expect(waitForMenu(menuInPlace: true, dropdownOpen: false, waited: 0.1))
    #expect(!waitForMenu(menuInPlace: true, dropdownOpen: false, waited: 0.6))
    // A dropdown is open: the user is in the menu, keep waiting however long.
    #expect(waitForMenu(menuInPlace: true, dropdownOpen: true, waited: 30))
    // The menu is leaving: go.
    #expect(!waitForMenu(menuInPlace: false, dropdownOpen: true, waited: 0))
}

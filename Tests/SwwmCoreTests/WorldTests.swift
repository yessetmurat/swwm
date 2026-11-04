//
//  WorldTests.swift
//  SwwmCoreTests
//
//  Created by Yesset Murat on 03.11.2026.
//

import CoreGraphics
import Testing
@testable import SwwmCore

let B = MonitorInfo(id: 1, name: "Color LCD", isBuiltin: true, frame: CGRect(x: 0, y: 0, width: 1512, height: 982))
let E = MonitorInfo(id: 2, name: "Some Display", isBuiltin: false, frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440))

func world(_ ms: [MonitorInfo], _ config: Config = .default) -> World {
    let w = World(config: config)
    w.updateMonitors(ms)
    return w
}

@Test func twoDisplays() {
    let w = world([B, E])
    #expect(w.workspaces(on: 1) == ["1", "2", "3", "4"])
    #expect(w.workspaces(on: 2) == ["q", "w", "e", "r"])
    #expect(w.activeWorkspace(on: 1) == "1")
    #expect(w.activeWorkspace(on: 2) == "q")
}

@Test func oneDisplayHoldsAll() {
    #expect(world([B]).workspaces(on: 1) == ["1", "2", "3", "4", "q", "w", "e", "r"])
}

@Test func externalOnlyIsHome() {
    let w = world([E])
    #expect(w.workspaces(on: 2) == ["1", "2", "3", "4", "q", "w", "e", "r"])
}

@Test func matchByNameIgnoresCase() throws {
    let c = try Config.parse("[[monitor]]\nmatch = \"some display\"\nworkspaces = [\"a\"]\n[[monitor]]\nmatch = \"built-in\"\nworkspaces = [\"b\"]")
    let w = world([B, E], c)
    #expect(w.workspaces(on: 2) == ["a"])
    #expect(w.workspaces(on: 1) == ["b"])
}

@Test func reconnectRestores() {
    let w = world([B, E])
    w.add(10, to: "q", floatingFrame: nil)
    w.show("w")
    w.updateMonitors([B])
    #expect(w.workspace(containing: 10)?.name == "q")
    #expect(w.monitor(of: "q") == 1)
    #expect(w.activeWorkspace(on: 1) == "1")
    w.updateMonitors([B, E])
    #expect(w.monitor(of: "q") == 2)
    #expect(w.activeWorkspace(on: 2) == "w")
    #expect(w.workspace(named: "q")?.tree.windows == [10])
}

@Test func unlistedDisplayGetsOwn() {
    let x = MonitorInfo(id: 3, name: "Third", isBuiltin: false, frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080))
    let w = world([B, E, x])
    #expect(w.workspaces(on: 3) == ["Third"])
    #expect(w.activeWorkspace(on: 3) == "Third")
}

@Test func focusStaysOnDisplay() {
    let w = world([B, E])
    w.add(1, to: "1", floatingFrame: nil)
    w.add(10, to: "q", floatingFrame: nil)
    w.noteFocused(1)
    w.noteFocused(10)
    #expect(w.remove(10) == 2)
    #expect(w.focusCandidate(on: 2) == nil)
    #expect(w.focusCandidate(on: 1) == 1)
}

@Test func focusMRU() {
    let w = world([B, E])
    w.add(10, to: "q", floatingFrame: nil)
    w.add(11, to: "q", floatingFrame: nil)
    w.noteFocused(11)
    w.noteFocused(10)
    _ = w.remove(10)
    #expect(w.focusCandidate(on: 2) == 11)
}

@Test func addSplitsFocused() {
    let w = world([B])
    w.add(1, to: "1", floatingFrame: nil)
    w.add(2, to: "1", floatingFrame: nil)
    w.add(3, to: "1", floatingFrame: nil)
    w.noteFocused(1)
    w.add(4, to: "1", floatingFrame: nil)  // splits 1, not the last leaf
    let f = w.workspace(named: "1")!.tree.frames(in: R, gap: 0)
    #expect(f[4] == CGRect(x: 0, y: 300, width: 500, height: 300))
}

@Test func floatingAndMove() {
    let w = world([B, E])
    let r = CGRect(x: 10, y: 10, width: 100, height: 100)
    w.add(5, to: "1", floatingFrame: r)
    #expect(w.workspace(named: "1")?.floating[5] == r)
    #expect(w.workspace(named: "1")?.tree.windows == [])
    w.move(5, to: "q")
    #expect(w.workspace(containing: 5)?.name == "q")
    #expect(w.workspace(named: "q")?.floating[5] == r)
}

@Test func stepWraps() {
    let w = world([B, E])
    w.show("4")
    #expect(w.step(on: 1, forward: true) == "1")
    w.show("1")
    #expect(w.step(on: 1, forward: false) == "4")
    #expect(w.step(on: 2, forward: true) == "w")
    #expect(world([B]).step(on: 1, forward: false) == "r")
}

@Test func neighborDisplay() {
    let w = world([B, E])
    #expect(w.monitorNeighbor(of: 1, .right) == 2)
    #expect(w.monitorNeighbor(of: 2, .left) == 1)
    #expect(w.monitorNeighbor(of: 1, .left) == nil)
}

@Test func workArea() {
    #expect(world([B]).workArea(of: 1) == CGRect(x: 8, y: 48, width: 1496, height: 926))
}

@Test func reloadKeepsWindows() throws {
    let w = world([B, E])
    w.add(10, to: "r", floatingFrame: nil)
    w.apply(config: try Config.parse("[[monitor]]\nmatch = \"built-in\"\nworkspaces = [\"1\"]"))
    #expect(w.workspaces(on: 1) == ["1"])
    #expect(w.workspaces(on: 2) == ["Some Display"])
    #expect(w.workspace(containing: 10) != nil)
}

@Test func monitorAtPoint() {
    let w = world([B, E])
    #expect(w.monitor(at: CGPoint(x: 2000, y: 700)) == 2)
    #expect(w.monitor(at: CGPoint(x: 100, y: 100)) == 1)
    #expect(w.monitor(at: CGPoint(x: -5000, y: 100)) == 1)  // off every display: home
}

@Test func visibility() {
    let w = world([B, E])
    w.add(1, to: "1", floatingFrame: nil)
    w.add(10, to: "w", floatingFrame: nil)
    #expect(w.isVisible(1))
    #expect(!w.isVisible(10))
    w.show("w")
    #expect(w.isVisible(10))
    w.updateMonitors([B])  // w now lives on B, which shows 1
    #expect(!w.isVisible(10))
    #expect(!w.isVisible(99))
}

@Test func shownFrameOfTileUsesConfigGap() {
    let w = world([B])
    let area = w.workArea(of: 1)
    w.add(1, to: "1", floatingFrame: nil)
    w.add(2, to: "1", floatingFrame: nil)
    #expect(w.shownFrame(of: 1) == w.workspace(named: "1")?.tree.frames(in: area, gap: w.config.settings.gap)[1])
}

@Test func shownFrameKeepsVisibleFloating() {
    let w = world([B])
    let f = CGRect(x: 100, y: 100, width: 300, height: 200)
    w.add(3, to: "q", floatingFrame: f)
    #expect(w.shownFrame(of: 3) == f)  // even on a hidden workspace
}

@Test func shownFrameCentersFloatingSliver() {
    let w = world([B])
    let area = w.workArea(of: 1)
    w.add(3, to: "1", floatingFrame: CGRect(x: 1510, y: 980, width: 300, height: 200))
    #expect(w.shownFrame(of: 3) == CGRect(x: area.midX - 150, y: area.midY - 100, width: 300, height: 200))
}

@Test func shownFrameOfZoomedIsWorkArea() {
    let w = world([B])
    w.add(1, to: "1", floatingFrame: nil)
    w.add(2, to: "1", floatingFrame: nil)
    w.workspace(named: "1")?.zoomed = 2
    #expect(w.shownFrame(of: 2) == w.workArea(of: 1))
}

@Test func shownFrameOfUnknownIsNil() {
    #expect(world([B]).shownFrame(of: 99) == nil)
}

@Test func replaceKeepsPlace() {
    let w = world([B])
    w.add(10, to: "1", floatingFrame: nil)
    w.add(11, to: "1", floatingFrame: nil)
    w.add(12, to: "1", floatingFrame: CGRect(x: 1, y: 2, width: 3, height: 4))
    let ws = w.workspace(named: "1")!
    ws.zoomed = 10
    let before = ws.tree.frames(in: w.workArea(of: 1), gap: 8)[10]
    w.replace(10, with: 20)
    w.replace(12, with: 22)
    #expect(ws.tree.windows == [20, 11])
    #expect(ws.tree.frames(in: w.workArea(of: 1), gap: 8)[20] == before)
    #expect(ws.zoomed == 20)
    #expect(ws.floating[22] == CGRect(x: 1, y: 2, width: 3, height: 4) && ws.floating[12] == nil)
    #expect(ws.mru == [22, 11, 20])
}

//
//  SavedWorkspacesTests.swift
//  SwwmCoreTests
//
//  Created by Yesset Murat on 03.11.2026.
//

import CoreGraphics
import Foundation
import Testing
@testable import SwwmCore

@Test func savedWorkspacesRoundTrip() throws {
    let w = world([B])
    w.add(10, to: "1", floatingFrame: nil)
    w.add(11, to: "3", floatingFrame: nil)
    let saved = SavedWorkspaces(world: w, pids: [10: 100, 11: 101])
    let back = try JSONDecoder().decode(SavedWorkspaces.self, from: JSONEncoder().encode(saved))
    #expect(back.workspace(of: 10, pid: 100) == "1")
    #expect(back.workspace(of: 11, pid: 101) == "3")
}

@Test func savedWorkspaceNeedsSamePid() {
    let w = world([B])
    w.add(10, to: "2", floatingFrame: nil)
    let saved = SavedWorkspaces(world: w, pids: [10: 100])
    #expect(saved.workspace(of: 10, pid: 999) == nil)  // a reused window ID after a reboot
    #expect(saved.workspace(of: 12, pid: 100) == nil)
}

private let rect = CGRect(x: 0, y: 0, width: 1000, height: 600)

@Test func treeShapeRestoresOrderAndRatios() {
    let a = DwindleTree()
    for w in [1, 2, 3] as [WindowID] { a.insert(w, splitting: nil) }
    a.root?.ratio = 0.3
    let b = DwindleTree()
    for w in [3, 1, 2] as [WindowID] { b.insert(w, splitting: nil) }  // adopted in another order
    b.restore(a.shape!)
    #expect(b.frames(in: rect, gap: 8) == a.frames(in: rect, gap: 8))
}

@Test func treeShapeDropsGoneWindowsAndKeepsNewOnes() {
    let a = DwindleTree()
    for w in [1, 2, 3] as [WindowID] { a.insert(w, splitting: nil) }
    let b = DwindleTree()
    for w in [3, 4, 1] as [WindowID] { b.insert(w, splitting: nil) }  // 2 closed, 4 is new
    b.restore(a.shape!)
    #expect(b.windows == [1, 3, 4])
}

@Test func savedActiveWorkspaceAndTreeComeBack() throws {
    let w = world([B])
    for id in [10, 11] as [WindowID] { w.add(id, to: "3", floatingFrame: nil) }
    w.workspace(named: "3")!.tree.root?.ratio = 0.7
    w.show("3")
    let data = try JSONEncoder().encode(SavedWorkspaces(world: w, pids: [10: 1, 11: 1]))

    let fresh = world([B])
    for id in [11, 10] as [WindowID] { fresh.add(id, to: "3", floatingFrame: nil) }
    fresh.restore(try JSONDecoder().decode(SavedWorkspaces.self, from: data))
    #expect(fresh.activeWorkspace(on: 1) == "3")
    #expect(fresh.workspace(named: "3")!.tree.frames(in: rect, gap: 0) == w.workspace(named: "3")!.tree.frames(in: rect, gap: 0))
}

@Test func savedFloatingFlag() throws {
    let w = world([B])
    w.add(10, to: "1", floatingFrame: CGRect(x: 0, y: 0, width: 100, height: 100))
    w.add(11, to: "1", floatingFrame: nil)
    let back = try JSONDecoder().decode(SavedWorkspaces.self, from: JSONEncoder().encode(SavedWorkspaces(world: w, pids: [10: 7, 11: 7])))
    #expect(back.wasFloating(10, pid: 7))
    #expect(!back.wasFloating(11, pid: 7))
    #expect(!back.wasFloating(10, pid: 8))
}

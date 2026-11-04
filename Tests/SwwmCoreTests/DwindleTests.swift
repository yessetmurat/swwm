//
//  DwindleTests.swift
//  SwwmCoreTests
//
//  Created by Yesset Murat on 03.11.2026.
//

import CoreGraphics
import Testing
@testable import SwwmCore

let R = CGRect(x: 0, y: 0, width: 1000, height: 600)

/// Inserts each id splitting the previous one.
func tree(_ ids: WindowID...) -> DwindleTree {
    let t = DwindleTree()
    var last: WindowID?
    for id in ids { t.insert(id, splitting: last); last = id }
    return t
}

/// 1 left, 2 top-right, 3 bottom-right.
func tree3() -> DwindleTree {
    let t = tree(1, 2)
    t.insert(3, splitting: 2)
    return t
}

@Test func oneWindowFills() {
    let t = DwindleTree()
    t.insert(1, splitting: nil)

    #expect(t.frames(in: R, gap: 0) == [1: R])
}

@Test func twoSideBySide() {
    #expect(tree(1, 2).frames(in: R, gap: 0) == [
        1: CGRect(x: 0, y: 0, width: 500, height: 600),
        2: CGRect(x: 500, y: 0, width: 500, height: 600),
    ])
}

@Test func threeDwindles() {
    let f = tree3().frames(in: R, gap: 0)

    #expect(f[1] == CGRect(x: 0, y: 0, width: 500, height: 600))
    #expect(f[2] == CGRect(x: 500, y: 0, width: 500, height: 300))
    #expect(f[3] == CGRect(x: 500, y: 300, width: 500, height: 300))
}

@Test func gapBetweenSiblings() {
    let f = tree(1, 2).frames(in: R, gap: 8)

    #expect(f[1] == CGRect(x: 0, y: 0, width: 496, height: 600))
    #expect(f[2] == CGRect(x: 504, y: 0, width: 496, height: 600))
}

@Test func removeCollapses() {
    let t = tree3()
    t.remove(2)

    #expect(t.frames(in: R, gap: 0) == [
        1: CGRect(x: 0, y: 0, width: 500, height: 600),
        3: CGRect(x: 500, y: 0, width: 500, height: 600),

    ])

    #expect(t.windows == [1, 3])
}

@Test func removeLastEmpties() {
    let t = tree(1)
    t.remove(1)

    #expect(t.windows.isEmpty)
    #expect(t.frames(in: R, gap: 0).isEmpty)
}

@Test func insertMissingTargetSplitsLast() {
    let t = tree(1, 2)
    t.insert(3, splitting: 99)

    #expect(t.frames(in: R, gap: 0)[3] == CGRect(x: 500, y: 300, width: 500, height: 300))
    #expect(t.contains(3))
    #expect(!t.contains(99))
}

@Test func swapExchanges() {
    let t = tree3()
    t.swap(1, 3)
    let f = t.frames(in: R, gap: 0)

    #expect(f[3] == CGRect(x: 0, y: 0, width: 500, height: 600))
    #expect(f[1] == CGRect(x: 500, y: 300, width: 500, height: 300))
}

@Test func warpFromLeft() {
    let t = tree3()
    t.warp(1, onto: 3, from: .left)
    // Without 1, (2,3) fills R side by side; 3's 500x600 cell then stacks 1 above 3.
    let f = t.frames(in: R, gap: 0)

    #expect(f[2] == CGRect(x: 0, y: 0, width: 500, height: 600))
    #expect(f[1] == CGRect(x: 500, y: 0, width: 500, height: 300))
    #expect(f[3] == CGRect(x: 500, y: 300, width: 500, height: 300))
}

@Test func warpFromRightGoesSecond() {
    let t = tree(1, 2, 3)  // 1 | 2 over 3
    t.warp(1, onto: 2, from: .right)
    // Without 1, (2,3) fills R side by side; 2's tall cell stacks 2 above 1.
    let f = t.frames(in: R, gap: 0)

    #expect(f[2] == CGRect(x: 0, y: 0, width: 500, height: 300))
    #expect(f[1] == CGRect(x: 0, y: 300, width: 500, height: 300))
}

@Test func mirrorY() {
    let t = tree(1, 2)
    t.mirror(.y, in: R)

    #expect(t.frames(in: R, gap: 0)[2]!.minX == 0)
}

@Test func mirrorX() {
    let t = tree3()
    t.mirror(.x, in: R)
    let f = t.frames(in: R, gap: 0)

    #expect(f[3]!.minY == 0)
    #expect(f[1]!.minX == 0)  // side-by-side split untouched
}

@Test func resizeThenBalance() {
    let t = tree(1, 2)
    t.resize(
        1,
        by: CGSize(width: 100, height: 0),
        in: R,
        gap: 0
    )

    #expect(t.frames(in: R, gap: 0)[1]!.width == 600)

    t.balance()

    #expect(t.frames(in: R, gap: 0)[1]!.width == 500)
}

@Test func resizeSecondChildMovesLeftEdge() {
    let t = tree(1, 2)
    t.resize(
        2,
        by: CGSize(width: -100, height: 0),
        in: R,
        gap: 0
    )  // drag left edge left

    #expect(t.frames(in: R, gap: 0)[2]!.width == 600)
}

@Test func resizeVertical() {
    let t = tree3()
    t.resize(
        2,
        by: CGSize(width: 0, height: 60),
        in: R,
        gap: 0
    )

    #expect(t.frames(in: R, gap: 0)[2]!.height == 360)
}

@Test func resizeClamps() {
    let t = tree(1, 2)
    t.resize(
        1,
        by: CGSize(width: 5000, height: 0),
        in: R,
        gap: 0
    )

    #expect(t.frames(in: R, gap: 0)[1]!.width == 900)
}

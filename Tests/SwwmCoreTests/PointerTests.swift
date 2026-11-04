//
//  PointerTests.swift
//  SwwmCoreTests
//
//  Created by Yesset Murat on 04.11.2026.
//

import CoreGraphics
import Testing
@testable import SwwmCore

private let p = CGPoint(x: 50, y: 50)
private let own: Int32 = 99

private func w(
    _ id: WindowID,
    layer: Int = 0,
    pid: Int32 = 1,
    alpha: Double = 1
) -> ServerWindow {
    ServerWindow(
        id: id,
        pid: pid,
        layer: layer,
        bounds: CGRect(x: 0, y: 0, width: 100, height: 100),
        alpha: alpha,
        owner: "App"
    )
}

@Test func tileUnderPointTakesFocus() {
    #expect(windowUnder(
        p,
        in: [w(2)],
        ownPID: own,
        raised: { _ in false }
    ) == 2)
}

@Test func overlayAboveTilesHidesThem() {
    // A context menu or the Dock over a tile: the tile must not take focus.
    #expect(windowUnder(
        p,
        in: [w(7, layer: 101), w(2)],
        ownPID: own,
        raised: { _ in false }
    ) == nil)
}

@Test func transparentOverlayIsSkipped() {
    #expect(windowUnder(
        p,
        in: [w(7, layer: 25, alpha: 0), w(2)],
        ownPID: own,
        raised: { _ in false }
    ) == 2)
}

@Test func cursorWindowIsSkipped() {
    let cursor = w(8, layer: Int(CGWindowLevelForKey(.cursorWindow)))
    #expect(windowUnder(
        p,
        in: [cursor, w(2)],
        ownPID: own,
        raised: { _ in false }
    ) == 2)
}

@Test func ownWindowHidesWhatIsUnder() {
    #expect(windowUnder(
        p,
        in: [w(5, layer: 25, pid: own), w(2)],
        ownPID: own,
        raised: { _ in false }
    ) == nil)
}

@Test func raisedFloatingWindowTakesFocus() {
    #expect(windowUnder(
        p,
        in: [w(4, layer: 3), w(2)],
        ownPID: own,
        raised: { $0 == 4 }
    ) == 4)
    #expect(windowUnder(
        p,
        in: [w(4, layer: 3), w(2)],
        ownPID: own,
        raised: { _ in false }
    ) == nil)
}

@Test func titleBarDragIsAMove() {
    let old = CGRect(x: 0, y: 0, width: 400, height: 300)
    #expect(nativeChange(
        from: old,
        to: old.offsetBy(dx: 50, dy: 0),
        pressedAt: CGPoint(x: 200, y: 10),
        clickCount: 1
    ) == .moved)
}

@Test func doubleClickIsIgnored() {
    let old = CGRect(x: 0, y: 0, width: 400, height: 300)
    #expect(nativeChange(
        from: old,
        to: CGRect(x: 0, y: 0, width: 800, height: 600),
        pressedAt: CGPoint(x: 200, y: 10),
        clickCount: 2
    ) == nil)
}

@Test func contentClickIsIgnored() {
    // A button that resizes its own window.
    let old = CGRect(x: 0, y: 0, width: 400, height: 300)
    #expect(nativeChange(
        from: old,
        to: CGRect(x: 0, y: 0, width: 500, height: 300),
        pressedAt: CGPoint(x: 200, y: 150),
        clickCount: 1
    ) == nil)
}

@Test func unchangedFrameIsNoChange() {
    let old = CGRect(x: 0, y: 0, width: 400, height: 300)
    #expect(nativeChange(
        from: old,
        to: old,
        pressedAt: CGPoint(x: 200, y: 10),
        clickCount: 1
    ) == nil)
}

@Test func rightEdgeResize() {
    let old = CGRect(x: 0, y: 0, width: 400, height: 300)
    #expect(nativeChange(
        from: old,
        to: CGRect(x: 0, y: 0, width: 450, height: 300),
        pressedAt: CGPoint(x: 398, y: 150),
        clickCount: 1
    )
        == .resized(CGSize(width: 50, height: 0)))
}

@Test func leftEdgeResize() {
    let old = CGRect(x: 100, y: 0, width: 400, height: 300)
    #expect(nativeChange(
        from: old,
        to: CGRect(x: 80, y: 0, width: 420, height: 300),
        pressedAt: CGPoint(x: 101, y: 150),
        clickCount: 1
    )
        == .resized(CGSize(width: -20, height: 0)))
}

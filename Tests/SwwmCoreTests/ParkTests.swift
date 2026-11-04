//
//  ParkTests.swift
//  SwwmCoreTests
//
//  Created by Yesset Murat on 04.11.2026.
//

import CoreGraphics
import Testing
@testable import SwwmCore

private let desk = -2147483603
private let p = CGPoint(x: 50, y: 50)

private func w(
    _ id: WindowID,
    layer: Int = 0,
    owner: String = "App",
    alpha: Double = 1
) -> ServerWindow {
    ServerWindow(
        id: id,
        pid: 1,
        layer: layer,
        bounds: CGRect(x: 0, y: 0, width: 100, height: 100),
        alpha: alpha,
        owner: owner
    )
}

private let desktop = w(9, layer: desk, owner: "Finder")

@Test func desktopOnTopMeansClick() {
    #expect(parkStep(
        at: p,
        onScreen: [desktop],
        leaving: [],
        desktopLayer: desk
    ) == .click)
}

@Test func leavingWindowsMeanWait() {
    #expect(parkStep(
        at: p,
        onScreen: [w(5), w(6), desktop],
        leaving: [5, 6],
        desktopLayer: desk
    ) == .wait([5, 6]))
}

@Test func windowNotLeavingMeansNoClick() {
    #expect(parkStep(
        at: p,
        onScreen: [w(5), w(7), desktop],
        leaving: [5],
        desktopLayer: desk
    ) == .noClick)
}

@Test func transparentWindowIsIgnored() {
    #expect(parkStep(
        at: p,
        onScreen: [w(7, alpha: 0), desktop],
        leaving: [],
        desktopLayer: desk
    ) == .click)
}

@Test func windowElsewhereIsIgnored() {
    let far = ServerWindow(
        id: 7,
        pid: 1,
        layer: 0,
        bounds: CGRect(x: 500, y: 0, width: 100, height: 100),
        alpha: 1,
        owner: "App"
    )
    #expect(parkStep(
        at: p,
        onScreen: [far, desktop],
        leaving: [],
        desktopLayer: desk
    ) == .click)
}

@Test func noDesktopMeansNoClick() {
    #expect(parkStep(
        at: p,
        onScreen: [],
        leaving: [],
        desktopLayer: desk
    ) == .noClick)
    #expect(parkStep(
        at: p,
        onScreen: [w(9, layer: desk, owner: "Dock")],
        leaving: [],
        desktopLayer: desk
    ) == .noClick)
}

@Test func cursorInAreaComesFirst() {
    let a = CGRect(x: 0, y: 0, width: 200, height: 100)

    #expect(parkPoints(cursor: CGPoint(x: 10, y: 10), area: a, mouseFollowsFocus: true) == [CGPoint(x: 10, y: 10), CGPoint(x: 100, y: 50)])
    #expect(parkPoints(cursor: CGPoint(x: 10, y: 10), area: a, mouseFollowsFocus: false) == [CGPoint(x: 10, y: 10)])
}

@Test func cursorElsewhereClicksOnlyWhenFollowing() {
    let a = CGRect(x: 0, y: 0, width: 200, height: 100)

    #expect(parkPoints(cursor: CGPoint(x: 500, y: 10), area: a, mouseFollowsFocus: true) == [CGPoint(x: 100, y: 50)])
    #expect(parkPoints(cursor: CGPoint(x: 500, y: 10), area: a, mouseFollowsFocus: false) == [])
}

@Test func cursorWindowIsIgnored() {
    // The window server lists the cursor as a window when it sits on the point.
    let cursor = w(2, layer: Int(CGWindowLevelForKey(.cursorWindow)), owner: "Window Server")
    #expect(parkStep(
        at: p,
        onScreen: [cursor, desktop],
        leaving: [],
        desktopLayer: desk
    ) == .click)
}

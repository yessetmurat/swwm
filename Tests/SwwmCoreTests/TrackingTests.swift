//
//  TrackingTests.swift
//  SwwmCoreTests
//
//  Created by Yesset Murat on 04.11.2026.
//

import CoreGraphics
import Testing
@testable import SwwmCore

private let tile = CGRect(x: 8, y: 48, width: 1496, height: 926)

private func snap(
    _ id: WindowID = 1,
    pid: Int32 = 10,
    app: String = "App",
    title: String = "t",
    frame: CGRect = tile,
    layer: Int = 0,
    subrole: String = "AXStandardWindow",
    resizable: Bool = true,
    fullScreen: Bool = false,
    minimized: Bool = false,
    listed: Set<WindowID> = [1]
) -> AppWindow {
    AppWindow(
        id: id,
        pid: pid,
        app: app,
        title: title,
        frame: frame,
        layer: layer,
        role: "AXWindow",
        subrole: subrole,
        isFullScreen: fullScreen,
        isMinimized: minimized,
        isResizable: resizable,
        hasFullScreenButton: true,
        listed: listed
    )
}

private func ctx(
    tiles: [WindowID: CGRect] = [:],
    child: Bool = false,
    adopting: Bool = false,
    hidden: Bool = false
) -> TrackContext {
    TrackContext(
        appTiles: tiles,
        isChild: child,
        adopting: adopting,
        appHidden: hidden,
        point: CGPoint(x: 100, y: 100)
    )
}

private func decide(
    _ s: AppWindow,
    _ c: TrackContext = ctx(),
    world w: World = world([B]),
    remembered: Remembered = Remembered(),
    saved: SavedWorkspaces? = nil
) -> TrackDecision {
    var r = remembered
    return trackDecision(
        s,
        world: w,
        context: c,
        remembered: &r,
        saved: saved
    )
}

private func saved(
    _ id: WindowID,
    pid: Int32,
    workspace: String,
    floating: Bool
) -> SavedWorkspaces {
    let w = world([B])
    w.add(id, to: workspace, floatingFrame: floating ? tile : nil)
    return SavedWorkspaces(world: w, pids: [id: pid])
}

@Test func nonStandardIsSkipped() {
    #expect(decide(snap(subrole: "AXDialog")) == .skip)
}

@Test func fullScreenAndMinimizedAreSkipped() {
    #expect(decide(snap(fullScreen: true)) == .skip)
    #expect(decide(snap(minimized: true)) == .skip)
}

@Test func raisedWindowIsSkippedUnlessChild() {
    #expect(decide(snap(layer: 3)) == .skip)
    #expect(decide(snap(layer: 3), ctx(child: true)) == .manage(workspace: "1", floating: false))
}

@Test func crashedRunFloatingIsAdopted() {
    let s = saved(
        1,
        pid: 10,
        workspace: "2",
        floating: true
    )

    #expect(decide(snap(layer: 3), ctx(adopting: true), saved: s) == .manage(workspace: "2", floating: true))
    #expect(decide(snap(layer: 3), ctx(adopting: false), saved: s) == .skip)
}

@Test func coveredTabIsTakenOver() {
    var r = Remembered()
    r.remember(1, .init(workspace: "2", pid: 10, floating: true))
    let d = trackDecision(
        snap(listed: [1]),
        world: world([B]),
        context: ctx(tiles: [7: tile]),
        remembered: &r,
        saved: nil
    )

    #expect(d == .takeOver(7))
    #expect(r.contains(1))
}

@Test func listedWindowIsNoCoveredTab() {
    #expect(decide(snap(listed: [1, 7]), ctx(tiles: [7: tile])) == .manage(workspace: "1", floating: false))
}

@Test func rememberedWorkspaceComesBack() {
    var r = Remembered()
    r.remember(1, .init(workspace: "2", pid: 10, floating: true))

    #expect(trackDecision(
        snap(),
        world: world([B]),
        context: ctx(),
        remembered: &r,
        saved: nil
    )
        == .manage(workspace: "2", floating: true))
    #expect(!r.contains(1))
}

@Test func rememberedWorkspaceDroppedByReloadFallsBack() {
    var r = Remembered()
    r.remember(1, .init(workspace: "x", pid: 10, floating: false))

    #expect(trackDecision(
        snap(),
        world: world([B]),
        context: ctx(),
        remembered: &r,
        saved: nil
    )
        == .manage(workspace: "1", floating: false))
}

@Test func savedWorkspaceApplies() {
    #expect(decide(snap(), saved: saved(
        1,
        pid: 10,
        workspace: "3",
        floating: false
    )) == .manage(workspace: "3", floating: false))
}

@Test func ruleWorkspaceApplies() throws {
    let w = world([B], try Config.parse(Config.defaultTOML + "\n[[rule]]\napp = \"^App$\"\nworkspace = \"4\""))
    #expect(decide(snap(), world: w) == .manage(workspace: "4", floating: false))
}

@Test func cursorDisplayIsTheDefault() {
    #expect(decide(snap()) == .manage(workspace: "1", floating: false))
}

@Test func floatsByRule() throws {
    let w = world([B], try Config.parse(Config.defaultTOML + "\n[[rule]]\napp = \"^App$\"\nfloat = true"))
    #expect(decide(snap(), world: w) == .manage(workspace: "1", floating: true))
}

@Test func floatsWhenNotResizable() {
    #expect(decide(snap(resizable: false)) == .manage(workspace: "1", floating: true))
}

@Test func floatsWhenSavedFloatingAndAdopting() {
    let s = saved(
        1,
        pid: 10,
        workspace: "1",
        floating: true
    )
    #expect(decide(snap(), ctx(adopting: true), saved: s) == .manage(workspace: "1", floating: true))
}

@Test func savedFloatingIgnoredWhenNotAdopting() {
    let s = saved(
        1,
        pid: 10,
        workspace: "1",
        floating: true
    )
    #expect(decide(snap(), ctx(adopting: false), saved: s) == .manage(workspace: "1", floating: false))
}

@Test func hiddenAppWindowsAreSkipped() {
    // AX still lists a hidden app's windows (a rescan after unlock).
    #expect(decide(snap(), ctx(hidden: true)) == .skip)
}

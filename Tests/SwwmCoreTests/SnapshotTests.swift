//
//  SnapshotTests.swift
//  SwwmCoreTests
//
//  Created by Yesset Murat on 03.11.2026.
//

import CoreGraphics
import Foundation
import Testing
@testable import SwwmCore

@Test func windowSnapshot() throws {
    let w = world([B, E])
    w.add(1, to: "1", floatingFrame: nil)
    w.add(10, to: "q", floatingFrame: CGRect(x: 1600, y: 100, width: 400, height: 300))
    let info: [WindowID: WindowInfo] = [
        1: WindowInfo(app: "Ghostty", title: "zsh", frame: CGRect(x: 8, y: 48, width: 1496, height: 926)),
        10: WindowInfo(app: "Calculator", title: "", frame: CGRect(x: 1600, y: 100, width: 400, height: 300)),
    ]
    let s = w.windowSnapshots(focused: 10) { info[$0] }

    #expect(s.map(\.id) == [1, 10])
    #expect(s[1] == WindowSnapshot(
        id: 10,
        app: "Calculator",
        title: "",
        workspace: "q",
        monitor: 2,
        floating: true,
        zoomed: false,
        visible: true,
        focused: true,
        frame: Frame(x: 1600, y: 100, width: 400, height: 300)
    ))
    #expect(!s[0].focused && !s[0].floating && s[0].visible)
    #expect(w.windowSnapshots(focused: nil) { _ in nil }.isEmpty)
}

@Test func workspaceAndMonitorSnapshots() {
    let w = world([B, E])
    w.add(1, to: "1", floatingFrame: nil)
    w.show("w")
    let ws = w.workspaceSnapshots()

    #expect(ws.map(\.name) == ["1", "2", "3", "4", "q", "w", "e", "r"])
    #expect(ws[0] == WorkspaceSnapshot(
        name: "1",
        monitor: 1,
        active: true,
        windows: [1]
    ))
    #expect(ws[5].active)

    let ms = w.monitorSnapshots(focusedMonitor: 2)

    #expect(ms.map(\.name) == ["Color LCD", "Some Display"])
    #expect(ms[1].active == "w" && ms[1].focused && ms[1].workspaces == ["q", "w", "e", "r"])
    #expect(!ms[0].focused && ms[0].builtin)
}

@Test func unicodeAndSpacesSurviveJSON() throws {
    let w = world([B])
    w.add(1, to: "1", floatingFrame: nil)
    let s = w.windowSnapshots(focused: nil) { _ in WindowInfo(app: "Telegram", title: "Сәлем \"мир\"", frame: .zero) }
    let back = try JSONDecoder().decode([WindowSnapshot].self, from: Data(json(s).utf8))

    #expect(back == s)
    #expect(json(s).contains("Сәлем"))
}

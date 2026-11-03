//
//  CommandTests.swift
//  SwwmCoreTests
//
//  Created by Yesset Murat on 03.11.2026.
//

import Testing
@testable import SwwmCore

@Test func parsesAll() throws {
    #expect(try Command.parse("focus left") == .focus(.left))
    #expect(try Command.parse("warp down") == .warp(.down))
    #expect(try Command.parse("swap up") == .swap(.up))
    #expect(try Command.parse("focus-monitor right") == .focusMonitor(.right))
    #expect(try Command.parse("move-to-monitor left") == .moveToMonitor(.left))
    #expect(try Command.parse("workspace q") == .workspace("q"))
    #expect(try Command.parse("move-to-workspace 2") == .moveToWorkspace("2"))
    #expect(try Command.parse("workspace-next") == .workspaceNext)
    #expect(try Command.parse("workspace-prev") == .workspacePrev)
    #expect(try Command.parse("mirror y") == .mirror(.y))
    #expect(try Command.parse("exec open -a \"Ghostty\"") == .exec("open -a \"Ghostty\""))
    #expect(try Command.parse("  toggle-float ") == .toggleFloat)
    #expect(try Command.parse("toggle-zoom") == .toggleZoom)
    #expect(try Command.parse("balance") == .balance)
    #expect(try Command.parse("reload") == .reload)
    #expect(try Command.parse("quit") == .quit)
}

@Test func rejects() {
    #expect(throws: CommandError.self) { try Command.parse("focus sideways") }
    #expect(throws: CommandError.self) { try Command.parse("focus-monitor up") }
    #expect(throws: CommandError.self) { try Command.parse("workspace") }
    #expect(throws: CommandError.self) { try Command.parse("exec") }
    #expect(throws: CommandError.self) { try Command.parse("fly") }
    #expect(throws: CommandError.self) { try Command.parse("balance now") }
}

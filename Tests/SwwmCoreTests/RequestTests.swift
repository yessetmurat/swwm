//
//  RequestTests.swift
//  SwwmCoreTests
//
//  Created by Yesset Murat on 03.11.2026.
//

import Testing
@testable import SwwmCore

@Test func parsesCommandsAndQueries() throws {
    #expect(try Request.parse(["focus", "left"]) == .command(.focus(.left)))
    #expect(try Request.parse(["move-to-workspace", "2"]) == .command(.moveToWorkspace("2")))
    #expect(try Request.parse(["reload"]) == .command(.reload))
    #expect(try Request.parse(["query", "windows"]) == .query(.windows))
    #expect(try Request.parse(["exec", "open", "-a", "Ghostty"]) == .command(.exec("open -a Ghostty")))
}

@Test func rejectsBadRequests() {
    #expect(throws: CommandError.self) { try Request.parse([]) }
    #expect(throws: CommandError.self) { try Request.parse(["query"]) }
    #expect(throws: CommandError.self) { try Request.parse(["query", "apps"]) }
    #expect(throws: CommandError.self) { try Request.parse(["fly"]) }
}

@Test func lineRoundTrips() throws {
    for r: Request in [.command(.workspace("q")), .query(.monitors), .command(.exec("open -a Ghostty"))] {
        #expect(try Request.parse(line: r.line) == r)
    }
}

@Test func replyWire() {
    #expect(Reply.ok("[]").wire == "ok\n[]")
    #expect(Reply.parse(wire: "ok\n[]") == .ok("[]"))
    #expect(Reply.parse(wire: "error\nunknown workspace 'z'") == .error("unknown workspace 'z'"))
    #expect(Reply.parse(wire: "") == .error("bad reply"))
}

@Test func noOpCommandIsOk() {
    #expect(Reply.ok().wire == "ok\n")
    #expect(Reply.parse(wire: "ok\n") == .ok())
}

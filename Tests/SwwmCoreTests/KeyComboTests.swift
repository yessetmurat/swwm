//
//  KeyComboTests.swift
//  SwwmCoreTests
//
//  Created by Yesset Murat on 03.11.2026.
//

import Testing
@testable import SwwmCore

@Test func parsesCombos() throws {
    #expect(try KeyCombo.parse("shift-alt-h") == KeyCombo(keyCode: 0x04, modifiers: [.shift, .alt]))
    #expect(try KeyCombo.parse("alt-shift-h") == KeyCombo(keyCode: 0x04, modifiers: [.shift, .alt]))
    #expect(try KeyCombo.parse("cmd-tab") == KeyCombo(keyCode: 0x30, modifiers: [.cmd]))
    #expect(try KeyCombo.parse("cmd-shift-tab") == KeyCombo(keyCode: 0x30, modifiers: [.cmd, .shift]))
    #expect(try KeyCombo.parse("alt-return") == KeyCombo(keyCode: 0x24, modifiers: [.alt]))
    #expect(try KeyCombo.parse("alt-1") == KeyCombo(keyCode: 0x12, modifiers: [.alt]))
    #expect(try KeyCombo.parse("ctrl-alt-q") == KeyCombo(keyCode: 0x0C, modifiers: [.ctrl, .alt]))
}

@Test func rejectsCombos() {
    #expect(throws: CommandError.self) { try KeyCombo.parse("hyper-h") }
    #expect(throws: CommandError.self) { try KeyCombo.parse("alt-") }
    #expect(throws: CommandError.self) { try KeyCombo.parse("alt-h-j") }
    #expect(throws: CommandError.self) { try KeyCombo.parse("alt-alt-h") }
}

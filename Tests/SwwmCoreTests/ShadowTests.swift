//
//  ShadowTests.swift
//  SwwmCoreTests
//
//  Created by Yesset Murat on 03.11.2026.
//

import Testing
@testable import SwwmCore

@Test func policyFollowsFloating() {
    #expect(shadowWanted(floating: false, mode: .float) == false)
    #expect(shadowWanted(floating: true, mode: .float) == true)
    #expect(shadowWanted(floating: true, mode: .off) == false)
    #expect(shadowWanted(floating: false, mode: .on) == nil)
}

@Test func shadowWire() {
    #expect(shadowMessage(window: 0x0102_0304, shadow: false) == [0x06, 0x00, 0x01, 0x04, 0x03, 0x02, 0x01, 0x00])
    #expect(shadowMessage(window: 1, shadow: true).last == 1)
}

@Test func shadowSetting() throws {
    #expect(Config.default.settings.windowShadow == .float)
    #expect(try Config.parse("[settings]\nwindow-shadow = \"off\"").settings.windowShadow == .off)
    #expect(throws: ConfigError.self) { try Config.parse("[settings]\nwindow-shadow = \"maybe\"") }
}

@Test func levelWire() {
    #expect(levelMessage(window: 0x0102_0304, level: 3) == [0x09, 0x00, 0x02, 0x04, 0x03, 0x02, 0x01, 0x03, 0x00, 0x00, 0x00])
    #expect(levelMessage(window: 1, level: 0).suffix(4) == [0, 0, 0, 0])
}

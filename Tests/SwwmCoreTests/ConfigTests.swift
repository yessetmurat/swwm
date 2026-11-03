//
//  ConfigTests.swift
//  SwwmCoreTests
//
//  Created by Yesset Murat on 03.11.2026.
//

import Testing
@testable import SwwmCore

private func err(_ s: String) -> String? {
    do { _ = try Config.parse(s); return nil } catch { return error.message }
}

@Test func defaultParses() throws {
    let c = Config.default
    #expect(c.allWorkspaces == ["1", "2", "3", "4", "q", "w", "e", "r"])
    #expect(c.monitors.map(\.match) == ["built-in", "*"])
    #expect(c.bindings[try KeyCombo.parse("alt-h")] == .focus(.left))
    #expect(c.bindings[try KeyCombo.parse("alt-j")] == .focus(.down))
    #expect(c.bindings[try KeyCombo.parse("ctrl-alt-l")] == .warp(.right))
    #expect(c.bindings[try KeyCombo.parse("shift-alt-g")] == .moveToMonitor(.right))
    #expect(c.bindings[try KeyCombo.parse("shift-alt-r")] == .moveToWorkspace("r"))
    #expect(c.bindings[try KeyCombo.parse("cmd-tab")] == .workspaceNext)
    #expect(c.bindings[try KeyCombo.parse("cmd-shift-tab")] == .workspacePrev)
    #expect(c.bindings[try KeyCombo.parse("shift-alt-y")] == .mirror(.y))
    #expect(c.bindings[try KeyCombo.parse("alt-return")] == .exec("open -a Ghostty"))
    #expect(c.bindings[try KeyCombo.parse("ctrl-alt-r")] == .reload)
    #expect(c.bindings[try KeyCombo.parse("ctrl-alt-s")] == nil)
    #expect(c.bindings.count == 46)
    #expect(c.settings == Settings())
}

@Test func defaultRules() {
    let rules = Config.default.rules
    #expect(rules.first { $0.matches(app: "Ghostty", title: "zsh") }?.workspace == "1")
    #expect(rules.first { $0.matches(app: "Discord", title: "") }?.workspace == "2")
    #expect(rules.first { $0.matches(app: "Telegram", title: "") }?.workspace == "2")
    #expect(!rules.contains { $0.matches(app: "Telegram Lite", title: "") })
    #expect(rules.contains { $0.matches(app: "Finder", title: "Copy") && $0.float == true })
    #expect(!rules.contains { $0.matches(app: "Finder", title: "Downloads") })
    #expect(rules.contains { $0.matches(app: "Tailscale", title: "") && $0.float == true })
}

@Test func settingsParse() throws {
    let c = try Config.parse("[settings]\ngap = 20\nmouse-modifier = \"ctrl-alt\"\nfocus-follows-mouse = false")
    #expect(c.settings.gap == 20)
    #expect(c.settings.padding == 8)
    #expect(c.settings.mouseModifier == [.ctrl, .alt])
    #expect(c.settings.focusFollowsMouse == false)
}

@Test func configErrors() {
    #expect(err("[settings]\ngap = ")?.contains("line 2") == true)
    #expect(err("[setings]")?.contains("setings") == true)
    #expect(err("[settings]\ngapp = 1")?.contains("gapp") == true)
    #expect(err("[settings]\ngap = \"wide\"")?.contains("gap") == true)
    #expect(err("[bindings]\n\"alt-h\" = \"fly\"")?.contains("alt-h") == true)
    #expect(err("[bindings]\n\"hyper-h\" = \"balance\"")?.contains("hyper-h") == true)
    #expect(err("[[monitor]]\nmatch=\"*\"\nworkspaces=[\"1\"]\n[bindings]\n\"alt-2\" = \"workspace 2\"")?.contains("unknown workspace '2'") == true)
    #expect(err("[[monitor]]\nmatch=\"a\"\nworkspaces=[\"1\"]\n[[monitor]]\nmatch=\"b\"\nworkspaces=[\"1\"]")?.contains("'1'") == true)
    #expect(err("[[monitor]]\nmatch=\"*\"\nworkspaces=[\"1\"]\n[[monitor]]\nmatch=\"*\"\nworkspaces=[\"2\"]") != nil)
    #expect(err("[[rule]]\napp = \"(\"")?.contains("(") == true)
    #expect(err("[[rule]]\napp = \"x\"\nworkspace = \"9\"")?.contains("unknown workspace '9'") == true)
}

@Test func barDefaults() {
    #expect(Config.default.bar == BarStyle())
}

@Test func barParses() throws {
    let c = try Config.parse("[bar]\nbackground = \"0x80112233\"\nlabel-font = \"Menlo:Bold:12.5\"")
    #expect(c.bar.background == 0x8011_2233)
    #expect(c.bar.labelFont == FontSpec(family: "Menlo", style: "Bold", size: 12.5))
    #expect(c.bar.foreground == 0xFFFF_FFFF)
}

@Test func barErrors() {
    #expect(err("[bar]\nbackground = \"red\"")?.contains("background") == true)
    #expect(err("[bar]\nlabel-font = \"Menlo:12\"")?.contains("label-font") == true)
    #expect(err("[bar]\nsize = 3")?.contains("size") == true)
}

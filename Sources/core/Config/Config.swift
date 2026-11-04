//
//  Config.swift
//  SwwmCore
//
//  Created by Yesset Murat on 03.11.2026.
//

import Foundation
import TOMLKit

public struct Config: Sendable {

    public var settings = Settings()
    public var monitors: [MonitorRule] = []
    public var bindings: [KeyCombo: Command] = [:]
    public var rules: [AppRule] = []
    public var bar = BarStyle()

    public var allWorkspaces: [String] { monitors.flatMap(\.workspaces) }

    public static var `default`: Config { try! parse(defaultTOML) }

    public static func parse(_ toml: String) throws(ConfigError) -> Config {
        let root: TOMLTable
        do {
            root = try TOMLTable(string: toml)
        } catch let e as TOMLParseError {
            throw ConfigError("line \(e.source.begin.line): \(e.description)")
        } catch {
            throw ConfigError("\(error)")
        }

        var c = Config()
        try checkKeys(root, ["settings", "monitor", "bindings", "rule", "bar"], in: "config")

        if let t = try table(root, "settings") {
            try checkKeys(t, ["gap", "padding", "bar-height", "focus-follows-mouse", "mouse-follows-focus", "mouse-modifier",
                              "window-shadow"], in: "settings")
            if let s = try string(t, "window-shadow") {
                guard let mode = ShadowMode(rawValue: s) else {
                    throw ConfigError("settings.window-shadow: '\(s)' must be \"float\", \"off\" or \"on\"")
                }
                c.settings.windowShadow = mode
            }
            if let v = try number(t, "gap") { c.settings.gap = v }
            if let v = try number(t, "padding") { c.settings.padding = v }
            if let v = try number(t, "bar-height") { c.settings.barHeight = v }
            if let v = try bool(t, "focus-follows-mouse") { c.settings.focusFollowsMouse = v }
            if let v = try bool(t, "mouse-follows-focus") { c.settings.mouseFollowsFocus = v }
            if let s = try string(t, "mouse-modifier") {
                var m: Modifiers = []
                for name in s.lowercased().split(separator: "-") {
                    guard let one = Modifiers.names[String(name)] else {
                        throw ConfigError("settings.mouse-modifier: bad modifier '\(name)'")
                    }
                    m.insert(one)
                }
                c.settings.mouseModifier = m
            }
        }

        var seen = Set<String>()
        var wildcard = false
        for t in try tables(root, "monitor") {
            try checkKeys(t, ["match", "workspaces"], in: "monitor")
            guard let match = try string(t, "match") else {
                throw ConfigError("monitor: missing 'match'")
            }
            guard let list = t["workspaces"]?.array else {
                throw ConfigError("monitor '\(match)': missing 'workspaces'")
            }
            var names: [String] = []
            for v in list {
                guard let n = v.string, !n.isEmpty else {
                    throw ConfigError("monitor '\(match)': workspace names must be strings")
                }
                guard seen.insert(n).inserted else {
                    throw ConfigError("workspace '\(n)' is listed twice")
                }
                names.append(n)
            }
            if match == "*" {
                guard !wildcard else {
                    throw ConfigError("only one monitor may match \"*\"")
                }
                wildcard = true
            }
            c.monitors.append(MonitorRule(match: match, workspaces: names))
        }

        func knownWorkspace(_ name: String, _ context: String) throws(ConfigError) {
            guard seen.contains(name) else {
                throw ConfigError("\(context): unknown workspace '\(name)'")
            }
        }

        if let t = try table(root, "bindings") {
            for key in t.keys {
                guard let value = t[key]?.string else {
                    throw ConfigError("binding '\(key)': value must be a string")
                }
                let combo: KeyCombo
                let command: Command
                do {
                    combo = try KeyCombo.parse(key)
                    command = try Command.parse(value)
                } catch {
                    throw ConfigError("binding '\(key)': \(error.message)")
                }
                switch command {
                case .workspace(let n), .moveToWorkspace(let n): try knownWorkspace(n, "binding '\(key)'")
                default: break
                }
                c.bindings[combo] = command
            }
        }

        for t in try tables(root, "rule") {
            try checkKeys(t, ["app", "title", "workspace", "float"], in: "rule")
            guard let app = try string(t, "app") else {
                throw ConfigError("rule: missing 'app'")
            }
            let title = try string(t, "title")
            let workspace = try string(t, "workspace")
            if let w = workspace { try knownWorkspace(w, "rule '\(app)'") }
            c.rules.append(AppRule(
                app: app,
                title: title,
                workspace: workspace,
                float: try bool(t, "float"),
                appRegex: try regex(app),
                titleRegex: try title.map { s throws(ConfigError) in try regex(s) }
            ))
        }

        if let t = try table(root, "bar") {
            try checkKeys(t, ["background", "item-background", "foreground", "workspace-font", "label-font"], in: "bar")
            if let v = try color(t, "background") { c.bar.background = v }
            if let v = try color(t, "item-background") { c.bar.itemBackground = v }
            if let v = try color(t, "foreground") { c.bar.foreground = v }
            if let v = try font(t, "workspace-font") { c.bar.workspaceFont = v }
            if let v = try font(t, "label-font") { c.bar.labelFont = v }
        }

        return c
    }

    // MARK: - helpers

    private static func color(_ t: TOMLTable, _ key: String) throws(ConfigError) -> UInt32? {
        guard let s = try string(t, key) else {
            return nil
        }
        let hex = s.lowercased()
        guard hex.hasPrefix("0x"), hex.count == 10, let v = UInt32(hex.dropFirst(2), radix: 16) else {
            throw ConfigError("bar.\(key): '\(s)' must be 0xAARRGGBB")
        }

        return v
    }

    private static func font(_ t: TOMLTable, _ key: String) throws(ConfigError) -> FontSpec? {
        guard let s = try string(t, key) else {
            return nil
        }
        do { return try FontSpec.parse(s) } catch { throw ConfigError("bar.\(key): \(error.message)") }
    }

    private static func checkKeys(_ t: TOMLTable, _ allowed: Set<String>, in context: String) throws(ConfigError) {
        if let bad = t.keys.first(where: { !allowed.contains($0) }) {
            throw ConfigError("\(context): unknown key '\(bad)'")
        }
    }

    private static func table(_ t: TOMLTable, _ key: String) throws(ConfigError) -> TOMLTable? {
        guard let v = t[key] else {
            return nil
        }
        guard let table = v.table else {
            throw ConfigError("'\(key)' must be a table")
        }
        return table
    }

    private static func tables(_ t: TOMLTable, _ key: String) throws(ConfigError) -> [TOMLTable] {
        guard let v = t[key] else {
            return []
        }
        guard let array = v.array else {
            throw ConfigError("'\(key)' must be written as [[\(key)]]")
        }

        var out: [TOMLTable] = []
        for item in array {
            guard let table = item.table else {
                throw ConfigError("'\(key)' must be written as [[\(key)]]")
            }
            out.append(table)
        }

        return out
    }

    private static func number(_ t: TOMLTable, _ key: String) throws(ConfigError) -> Double? {
        guard let v = t[key] else {
            return nil
        }
        if let i = v.int { return Double(i) }
        if let d = v.double { return d }
        throw ConfigError("'\(key)' must be a number")
    }

    private static func bool(_ t: TOMLTable, _ key: String) throws(ConfigError) -> Bool? {
        guard let v = t[key] else {
            return nil
        }
        guard let b = v.bool else {
            throw ConfigError("'\(key)' must be true or false")
        }
        return b
    }

    private static func string(_ t: TOMLTable, _ key: String) throws(ConfigError) -> String? {
        guard let v = t[key] else {
            return nil
        }
        guard let s = v.string else {
            throw ConfigError("'\(key)' must be a string")
        }
        return s
    }

    private static func regex(_ s: String) throws(ConfigError) -> NSRegularExpression {
        do { return try NSRegularExpression(pattern: s) } catch { throw ConfigError("bad regular expression '\(s)'") }
    }
}

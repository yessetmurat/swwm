//
//  Request.swift
//  SwwmCore
//
//  Created by Yesset Murat on 03.11.2026.
//

public enum QueryKind: String, Sendable, CaseIterable {

    case windows, workspaces, monitors
}

/// One CLI request. The client sends `line` + "\n"; the app parses it back.
public enum Request: Equatable, Sendable {

    case command(Command)
    case query(QueryKind)

    /// From CLI arguments, already split by the shell.
    public static func parse(_ args: [String]) throws(CommandError) -> Request {
        try parse(line: args.joined(separator: " "))
    }

    public static func parse(line: String) throws(CommandError) -> Request {
        let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let first = parts.first else { throw CommandError("no command") }
        guard first == "query" else { return .command(try Command.parse(line)) }
        guard parts.count == 2, let kind = QueryKind(rawValue: parts[1]) else {
            throw CommandError("usage: query \(QueryKind.allCases.map(\.rawValue).joined(separator: "|"))")
        }
        return .query(kind)
    }

    public var line: String {
        switch self {
        case .command(let c): c.text
        case .query(let k): "query \(k.rawValue)"
        }
    }
}

extension Command {

    /// The text `Command.parse` reads back as this command.
    public var text: String {
        switch self {
        case .focus(let d): "focus \(d.rawValue)"
        case .swap(let d): "swap \(d.rawValue)"
        case .warp(let d): "warp \(d.rawValue)"
        case .focusMonitor(let d): "focus-monitor \(d.rawValue)"
        case .moveToMonitor(let d): "move-to-monitor \(d.rawValue)"
        case .workspace(let n): "workspace \(n)"
        case .moveToWorkspace(let n): "move-to-workspace \(n)"
        case .workspaceNext: "workspace-next"
        case .workspacePrev: "workspace-prev"
        case .toggleFloat: "toggle-float"
        case .toggleZoom: "toggle-zoom"
        case .balance: "balance"
        case .mirror(let a): "mirror \(a.rawValue)"
        case .exec(let s): "exec \(s)"
        case .reload: "reload"
        case .quit: "quit"
        }
    }
}

/// The app's answer: "ok\n<body>" or "error\n<message>".
public struct Reply: Equatable, Sendable {

    public var ok: Bool
    public var body: String  // JSON for queries, "" for commands, the message for errors

    public static func ok(_ body: String = "") -> Reply { Reply(ok: true, body: body) }
    public static func error(_ message: String) -> Reply { Reply(ok: false, body: message) }

    public var wire: String { (ok ? "ok" : "error") + "\n" + body }

    public static func parse(wire: String) -> Reply {
        guard let nl = wire.firstIndex(of: "\n") else { return .error("bad reply") }
        let body = String(wire[wire.index(after: nl)...])
        switch wire[..<nl] {
        case "ok": return .ok(body)
        case "error": return .error(body)
        default: return .error("bad reply")
        }
    }
}

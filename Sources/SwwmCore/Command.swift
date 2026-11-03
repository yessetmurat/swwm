//
//  Command.swift
//  SwwmCore
//
//  Created by Yesset Murat on 03.11.2026.
//

import Foundation

public typealias WindowID = UInt32   // CGWindowID
public typealias MonitorID = UInt32  // CGDirectDisplayID

public enum Direction: String, Sendable { case left, down, up, right }
public enum Axis: String, Sendable { case x, y }

public struct CommandError: Error, Equatable, Sendable {

    public let message: String
    public init(_ message: String) { self.message = message }
}

/// An action, written the same way in config bindings and on the CLI.
public enum Command: Equatable, Sendable {

    case focus(Direction), swap(Direction), warp(Direction)
    case focusMonitor(Direction), moveToMonitor(Direction)  // .left / .right only
    case workspace(String), moveToWorkspace(String)
    case workspaceNext, workspacePrev
    case toggleFloat, toggleZoom, balance, mirror(Axis)
    case exec(String), reload, quit

    public static func parse(_ s: String) throws(CommandError) -> Command {
        let line = s.trimmingCharacters(in: .whitespaces)
        let parts = line.split(separator: " ", maxSplits: 1)
        let verb = parts.first.map(String.init) ?? ""
        let arg = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""

        func noArg(_ c: Command) throws(CommandError) -> Command {
            guard arg.isEmpty else { throw CommandError("'\(verb)' takes no argument: '\(line)'") }
            return c
        }
        func name() throws(CommandError) -> String {
            guard !arg.isEmpty, !arg.contains(" ") else { throw CommandError("'\(verb)' needs one name: '\(line)'") }
            return arg
        }
        func direction(horizontalOnly: Bool = false) throws(CommandError) -> Direction {
            guard let d = Direction(rawValue: arg), !horizontalOnly || d == .left || d == .right else {
                throw CommandError("bad direction in '\(line)'")
            }
            return d
        }

        switch verb {
        case "focus": return .focus(try direction())
        case "swap": return .swap(try direction())
        case "warp": return .warp(try direction())
        case "focus-monitor": return .focusMonitor(try direction(horizontalOnly: true))
        case "move-to-monitor": return .moveToMonitor(try direction(horizontalOnly: true))
        case "workspace": return .workspace(try name())
        case "move-to-workspace": return .moveToWorkspace(try name())
        case "workspace-next": return try noArg(.workspaceNext)
        case "workspace-prev": return try noArg(.workspacePrev)
        case "toggle-float": return try noArg(.toggleFloat)
        case "toggle-zoom": return try noArg(.toggleZoom)
        case "balance": return try noArg(.balance)
        case "mirror":
            guard let a = Axis(rawValue: arg) else { throw CommandError("bad axis in '\(line)'") }
            return .mirror(a)
        case "exec":
            guard !arg.isEmpty else { throw CommandError("'exec' needs a command") }
            return .exec(arg)
        case "reload": return try noArg(.reload)
        case "quit": return try noArg(.quit)
        default: throw CommandError("unknown command '\(line)'")
        }
    }
}

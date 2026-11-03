//
//  Client.swift
//  swwm
//
//  Created by Yesset Murat on 03.11.2026.
//

import Foundation
import SwwmCore

/// `swwm <command>`: sends one request to the running swwm and prints the reply.
enum Client {

    static let usage = """
        usage: swwm                      start the window manager
               swwm <command>            run a command, as in the config's bindings
               swwm query windows|workspaces|monitors
               swwm --version
        commands: focus|swap|warp left|down|up|right, focus-monitor left|right,
                  move-to-monitor left|right, workspace <name>, move-to-workspace <name>,
                  workspace-next, workspace-prev, toggle-float, toggle-zoom, balance,
                  mirror x|y, exec <shell command>, reload, quit
        exit codes: 0 ok, 1 rejected, 2 swwm not running, 64 usage
        """

    static func run(_ args: [String]) -> Never {
        if args == ["--help"] || args == ["-h"] { fail(usage, 64) }
        if args == ["--version"] {
            // Stamped into the embedded Info.plist by `make release`; "dev" otherwise.
            print(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")
            exit(0)
        }
        let request: Request
        do { request = try Request.parse(args) } catch { fail("swwm: \(error.message)\n\(usage)", 64) }
        switch send(request.line, timeout: 2) {
        case .notRunning: fail("swwm is not running", 2)
        case .noAnswer: fail("swwm did not answer", 2)
        case .reply(let r) where r.ok:
            if !r.body.isEmpty { print(r.body) }
            exit(0)
        case .reply(let r): fail("swwm: \(r.body)", 1)
        }
    }

    /// True when another swwm listens on the socket, busy or not.
    static func isRunning() -> Bool {
        let fd = Socket.make()
        defer { close(fd) }
        var addr = Socket.address()
        return withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        } == 0
    }

    private enum Outcome {
        case notRunning, noAnswer, reply(Reply)
    }

    private static func send(_ line: String, timeout: Double) -> Outcome {
        let fd = Socket.make()
        defer { close(fd) }
        var addr = Socket.address()
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { return .notRunning }
        Socket.setTimeout(fd, seconds: timeout)
        Socket.write(fd, line + "\n")
        shutdown(fd, SHUT_WR)
        guard let text = Socket.read(fd), !text.isEmpty else { return .noAnswer }
        return .reply(Reply.parse(wire: text))
    }

    private static func fail(_ message: String, _ code: Int32) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(code)
    }
}

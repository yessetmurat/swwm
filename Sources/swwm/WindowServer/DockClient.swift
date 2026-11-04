//
//  DockClient.swift
//  swwm
//
//  Created by Yesset Murat on 03.11.2026.
//

import Foundation
import SwwmCore

/// Sends shadow and window-level requests to the payload loaded in Dock.
/// Unreachable when the module is not installed or Dock has not been injected
/// yet; an older payload rejects level requests.
final class DockClient {

    /// What came back: no payload listening, a payload that turned the request
    /// down (an older one does for level requests), or done.
    enum Reply {

        case unreachable, rejected, done
    }

    private let queue = DispatchQueue(label: "dev.swwm.dock")
    // Workaround: the loader injects the payload a few seconds after a Dock
    // restart and does not tell swwm; swwm asks again at this interval.
    private static let reachableRetry = 0.5
    private var path: String { (NSTemporaryDirectory() as NSString).appendingPathComponent(DockSocket.name) }

    /// Off the main thread; `done` (if given) runs on the main queue.
    func setShadow(_ id: WindowID, _ shadow: Bool, done: ((Bool) -> Void)? = nil) {
        queue.async { [path] in
            let ok = Self.send(shadowMessage(window: id, shadow: shadow), to: path) == .done
            if let done { DispatchQueue.main.async { done(ok) } }
        }
    }

    /// Blocks until every message is sent or times out; for quit.
    func setShadowsSync(_ items: [(id: WindowID, shadow: Bool)]) {
        queue.sync { [path] in
            for i in items { _ = Self.send(shadowMessage(window: i.id, shadow: i.shadow), to: path) }
        }
    }

    /// Off the main thread; `done` (if given) runs on the main queue.
    func setLevel(_ id: WindowID, _ level: Int32, done: ((Reply) -> Void)? = nil) {
        queue.async { [path] in
            let reply = Self.send(levelMessage(window: id, level: level), to: path)
            if let done { DispatchQueue.main.async { done(reply) } }
        }
    }

    /// Blocks until every message is sent or times out; for quit.
    func setLevelsSync(_ items: [(id: WindowID, level: Int32)]) {
        queue.sync { [path] in
            for i in items { _ = Self.send(levelMessage(window: i.id, level: i.level), to: path) }
        }
    }

    /// Calls `done` on the main queue once the payload answers: after a Dock
    /// restart the loader injects it a few seconds later. Asks with a request
    /// every payload reads in full and turns down (window 0), never a bare
    /// connect: an older payload dies of a connection closed before its reply.
    /// Gives up after `timeout` seconds.
    func whenReachable(timeout: TimeInterval = 30, _ done: @escaping () -> Void) {
        queue.async { [path] in
            let end = Date().addingTimeInterval(timeout)

            while Date() < end {
                if Self.send(shadowMessage(window: 0, shadow: true), to: path) != .unreachable {
                    DispatchQueue.main.async(execute: done)
                    return
                }
                Thread.sleep(forTimeInterval: Self.reachableRetry)
            }
        }
    }

    private static func send(_ bytes: [UInt8], to path: String) -> Reply {
        let fd = connect(to: path)
        guard fd >= 0 else {
            return .unreachable
        }
        defer { close(fd) }

        let sent = bytes.withUnsafeBytes { buffer in
            Darwin.send(
                fd,
                buffer.baseAddress,
                buffer.count,
                0
            )
        }
        guard sent == bytes.count else {
            return .unreachable
        }

        var reply: UInt8 = 0
        let received = recv(
            fd,
            &reply,
            1,
            0
        )
        guard received == 1 else {
            return .unreachable
        }

        return reply == 1 ? .done : .rejected
    }

    /// A connected socket, or -1.
    private static func connect(to path: String) -> Int32 {
        let fd = Socket.make()
        guard fd >= 0 else {
            return -1
        }

        Socket.setTimeout(fd, seconds: 0.2)
        var addr = Socket.address(path: path)
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else {
            close(fd)
            return -1
        }
        return fd
    }
}

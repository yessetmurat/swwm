//
//  ShadowClient.swift
//  swwm
//
//  Created by Yesset Murat on 03.11.2026.
//

import Foundation
import SwwmCore

/// Sends shadow requests to the payload loaded in Dock. Unreachable when the
/// module is not installed or Dock has not been injected yet.
final class ShadowClient {

    private let queue = DispatchQueue(label: "dev.swwm.shadows")
    private var path: String { (NSTemporaryDirectory() as NSString).appendingPathComponent(ShadowSocket.name) }

    /// Off the main thread; `done` (if given) runs on the main queue.
    func set(_ id: WindowID, shadow: Bool, done: ((Bool) -> Void)? = nil) {
        queue.async { [path] in
            let ok = Self.send(shadowMessage(window: id, shadow: shadow), to: path)
            if let done { DispatchQueue.main.async { done(ok) } }
        }
    }

    /// Blocks until every message is sent or times out; for quit.
    func setSync(_ items: [(id: WindowID, shadow: Bool)]) {
        queue.sync { [path] in
            for i in items { _ = Self.send(shadowMessage(window: i.id, shadow: i.shadow), to: path) }
        }
    }

    private static func send(_ bytes: [UInt8], to path: String) -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var tv = timeval(tv_sec: 0, tv_usec: 200_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { dst in
            path.utf8CString.withUnsafeBytes { src in
                dst.copyMemory(from: UnsafeRawBufferPointer(rebasing: src.prefix(dst.count - 1)))
            }
        }
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { return false }
        let sent = bytes.withUnsafeBytes { Darwin.send(fd, $0.baseAddress, $0.count, 0) }
        guard sent == bytes.count else { return false }
        var reply: UInt8 = 0
        return recv(fd, &reply, 1, 0) == 1 && reply == 1
    }
}

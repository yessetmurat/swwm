//
//  CommandServer.swift
//  swwm
//
//  Created by Yesset Murat on 03.11.2026.
//

import Foundation
import SwwmCore

/// The Unix socket shared by the app and the CLI: per user, in the user's
/// temporary directory.
enum Socket {

    static var path: String { (NSTemporaryDirectory() as NSString).appendingPathComponent("swwm.sock") }

    static func address() -> sockaddr_un {
        var a = sockaddr_un()
        a.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &a.sun_path) { dst in
            path.utf8CString.withUnsafeBytes { src in
                dst.copyMemory(from: UnsafeRawBufferPointer(rebasing: src.prefix(dst.count - 1)))
            }
        }
        return a
    }

    /// A stream socket that never raises SIGPIPE.
    static func make() -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        return fd
    }

    static func setTimeout(_ fd: Int32, seconds: Double) {
        var tv = timeval(tv_sec: Int(seconds), tv_usec: Int32((seconds - Double(Int(seconds))) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    }

    /// Reads until EOF (or, with `untilNewline`, the first newline). nil on timeout or error.
    static func read(_ fd: Int32, untilNewline: Bool = false) -> String? {
        var data = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while data.count < 1 << 20 {
            let n = Darwin.read(fd, &buf, buf.count)
            if n < 0 { return nil }
            if n == 0 { break }
            data.append(contentsOf: buf[0..<n])
            if untilNewline, buf[0..<n].contains(UInt8(ascii: "\n")) { break }
        }
        return String(decoding: data, as: UTF8.self)
    }

    static func write(_ fd: Int32, _ s: String) {
        var bytes = Array(s.utf8)[...]
        while !bytes.isEmpty {
            let n = bytes.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
            if n <= 0 { return }
            bytes = bytes.dropFirst(n)
        }
    }
}

/// Answers CLI requests. Sockets are served on a private queue; each request
/// runs on the main queue, where all window-manager state lives.
final class CommandServer {

    private let handle: (Request) -> Reply
    private let queue = DispatchQueue(label: "dev.swwm.socket")
    private var fd: Int32 = -1

    init(handle: @escaping (Request) -> Reply) {
        self.handle = handle
    }

    func start() {
        unlink(Socket.path)  // left by a crash
        fd = Socket.make()
        var addr = Socket.address()
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, listen(fd, 16) == 0 else {
            log.error("cannot listen on \(Socket.path, privacy: .public): \(String(cString: strerror(errno)), privacy: .public)")
            return
        }
        chmod(Socket.path, 0o600)
        let listener = fd
        queue.async { [weak self] in
            while true {
                let c = accept(listener, nil, nil)
                if c < 0 {
                    if errno == EINTR { continue }
                    return  // closed by stop()
                }
                self?.serve(c)
            }
        }
    }

    func stop() {
        guard fd >= 0 else { return }
        close(fd)
        fd = -1
        unlink(Socket.path)
    }

    private func serve(_ c: Int32) {
        defer { close(c) }
        var on: Int32 = 1
        setsockopt(c, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        Socket.setTimeout(c, seconds: 1)
        guard let text = Socket.read(c, untilNewline: true) else { return }
        let line = text.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) ?? ""
        let reply: Reply
        do {
            let request = try Request.parse(line: line)
            reply = DispatchQueue.main.sync { handle(request) }
        } catch {
            reply = .error(error.message)
        }
        Socket.write(c, reply.wire)
    }
}

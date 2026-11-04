//
//  Socket.swift
//  swwm
//
//  Created by Yesset Murat on 03.11.2026.
//

import Foundation

/// The Unix socket shared by the app and the CLI: per user, in the user's
/// temporary directory.
enum Socket {

    static var path: String { (NSTemporaryDirectory() as NSString).appendingPathComponent("swwm.sock") }

    static func address(path: String = path) -> sockaddr_un {
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

    /// For reads and writes.
    static func setTimeout(_ fd: Int32, seconds: Double) {
        var tv = timeval(tv_sec: Int(seconds), tv_usec: Int32((seconds - Double(Int(seconds))) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
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

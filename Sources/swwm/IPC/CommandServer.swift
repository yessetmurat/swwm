//
//  CommandServer.swift
//  swwm
//
//  Created by Yesset Murat on 03.11.2026.
//

import Foundation
import SwwmCore

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

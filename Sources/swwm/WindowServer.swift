//
//  WindowServer.swift
//  swwm
//
//  Created by Yesset Murat on 04.11.2026.
//

import CoreGraphics
import Foundation
import SwwmCore

/// SkyLight, the window server's private client framework. Needs no SIP
/// change; a missing symbol means the feature that wants it is off.
enum SkyLight {

    private static let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

    static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle, let p = dlsym(handle, name) else { return nil }
        return unsafeBitCast(p, to: type)
    }

    /// swwm's own connection to the window server.
    static let connection: Int32 = symbol("SLSMainConnectionID", as: (@convention(c) () -> Int32).self)?() ?? 0
}

/// The window list and window events, straight from the window server: it
/// knows of a window as soon as it is on screen, before its app reports it.
enum WindowServer {

    private typealias Callback = @convention(c) (UInt32, UnsafeMutableRawPointer?, Int, UnsafeMutableRawPointer?) -> Void
    private typealias Register = @convention(c) (Int32, Callback, UInt32, UnsafeMutableRawPointer?) -> Int32
    private typealias Request = @convention(c) (Int32, UnsafeMutablePointer<UInt32>?, Int32) -> Int32

    nonisolated(unsafe) private static var handler: (WindowServerEvent) -> Void = { _ in }

    /// On-screen windows, front to back.
    static func onScreen(excludingDesktop: Bool = false) -> [ServerWindow] {
        let options: CGWindowListOption = excludingDesktop ? [.optionOnScreenOnly, .excludeDesktopElements] : .optionOnScreenOnly
        return list(CGWindowListCopyWindowInfo(options, kCGNullWindowID))
    }

    /// One window, on screen or not; nil when it is gone.
    static func window(_ id: WindowID) -> ServerWindow? {
        list(CGWindowListCopyWindowInfo(.optionIncludingWindow, id)).first
    }

    /// Calls `handler` on the main thread for every `WindowServerEvent`.
    /// Events arrive through the main run loop.
    static func start(_ handler: @escaping (WindowServerEvent) -> Void) {
        self.handler = handler
        guard let register = SkyLight.symbol("SLSRegisterConnectionNotifyProc", as: Register.self) else { return }
        let callback: Callback = { type, data, length, _ in
            let bytes = data.map { Array(UnsafeRawBufferPointer(start: $0, count: length)) } ?? []
            if let e = WindowServerEvent(type: type, data: bytes) { WindowServer.handler(e) }
        }
        for type in WindowServerEvent.types { _ = register(SkyLight.connection, callback, type, nil) }
    }

    /// Moved and resized events come only for windows asked for here; pass
    /// every window to watch each time.
    static func watch(_ ids: [WindowID]) {
        guard let request = SkyLight.symbol("SLSRequestNotificationsForWindows", as: Request.self) else { return }
        var ids = ids
        _ = request(SkyLight.connection, &ids, Int32(ids.count))
    }

    private static func list(_ info: CFArray?) -> [ServerWindow] {
        (info as? [[String: Any]] ?? []).compactMap { i in
            guard let id = i[kCGWindowNumber as String] as? Int,
                  let dict = i[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict) else { return nil }
            return ServerWindow(id: WindowID(id), pid: i[kCGWindowOwnerPID as String] as? Int32 ?? 0,
                                layer: i[kCGWindowLayer as String] as? Int ?? 0, bounds: bounds,
                                alpha: i[kCGWindowAlpha as String] as? Double ?? 1,
                                owner: i[kCGWindowOwnerName as String] as? String ?? "")
        }
    }
}

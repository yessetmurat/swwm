//
//  SkyLight.swift
//  swwm
//
//  Created by Yesset Murat on 04.11.2026.
//

import CoreGraphics
import Foundation

/// SkyLight, the window server's private client framework. Needs no SIP
/// change; a missing symbol means the feature that wants it is off.
enum SkyLight {

    private static let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

    static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle, let p = dlsym(handle, name) else {
            return nil
        }
        return unsafeBitCast(p, to: type)
    }

    /// swwm's own connection to the window server.
    static let connection: Int32 = symbol("SLSMainConnectionID", as: (@convention(c) () -> Int32).self)?() ?? 0
}

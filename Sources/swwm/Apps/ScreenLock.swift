//
//  ScreenLock.swift
//  swwm
//
//  Created by Yesset Murat on 04.11.2026.
//

import AppKit
import os
import SwwmCore

/// Whether the screen is locked; any thread.
final class ScreenLock: Sendable {

    private let locked = OSAllocatedUnfairLock(initialState: ScreenLock.lockedNow)

    var isLocked: Bool {
        get { locked.withLock { $0 } }
        set { locked.withLock { $0 = newValue } }
    }

    private static var lockedNow: Bool {
        (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
    }
}

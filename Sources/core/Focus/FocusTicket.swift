//
//  FocusTicket.swift
//  SwwmCore
//
//  Created by Yesset Murat on 04.11.2026.
//

import os

/// Focus is latest-wins across all apps: each focus command carries a
/// ticket, and one whose ticket is no longer current when its app gets to
/// it is dropped, so an app that was busy does not take the keyboard back.
/// Thread-safe.
public final class FocusTicket: Sendable {

    private let value = OSAllocatedUnfairLock(initialState: 0)

    public init() {}

    /// A new ticket; every earlier one is stale from now on.
    public func next() -> Int { value.withLock { $0 += 1; return $0 } }

    public var current: Int { value.withLock { $0 } }

    /// Runs `steps` in order while `ticket` is current: an app may answer
    /// one step only after a long stall, and focus may have moved on by then.
    public func run(_ ticket: Int, _ steps: [() -> Void]) {
        for step in steps {
            guard current == ticket else { return }
            step()
        }
    }
}

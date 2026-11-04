//
//  PendingWrites.swift
//  SwwmCore
//
//  Created by Yesset Murat on 04.11.2026.
//

import os

/// The latest write per window that has not run yet: a drag sends many, and
/// only the newest matters. `put` says whether a run must be queued for it;
/// a window swwm forgot gets none of its queued writes. Thread-safe.
public final class PendingWrites<Value: Sendable>: Sendable {

    private let state = OSAllocatedUnfairLock(initialState: [WindowID: Value]())

    public init() {}

    /// True when no write for `id` was pending: queue a run that takes it.
    public func put(_ id: WindowID, _ value: Value) -> Bool {
        state.withLock { pending in
            defer { pending[id] = value }
            return pending[id] == nil
        }
    }

    public func take(_ id: WindowID) -> Value? {
        state.withLock { $0.removeValue(forKey: id) }
    }

    public func forget(_ id: WindowID) {
        state.withLock { _ = $0.removeValue(forKey: id) }
    }
}

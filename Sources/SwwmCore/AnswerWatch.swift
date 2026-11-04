//
//  AnswerWatch.swift
//  SwwmCore
//
//  Created by Yesset Murat on 04.11.2026.
//

import Foundation

/// The windows whose writes an app left unanswered (stopped, or busy longer
/// than the wait): once the app answers again, they are placed again.
public struct AnswerWatch: Sendable {

    private var missed: Set<WindowID> = []

    public init() {}

    public mutating func noAnswer(_ id: WindowID) { missed.insert(id) }

    /// The windows to place again, once.
    public mutating func answered() -> Set<WindowID> {
        defer { missed = [] }
        return missed
    }
}

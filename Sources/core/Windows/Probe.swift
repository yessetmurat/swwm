//
//  Probe.swift
//  SwwmCore
//
//  Created by Yesset Murat on 04.11.2026.
//

public enum ProbeStep: Equatable, Sendable {

    case float                  // stretches one way only: floats where it opened
    case tile(learned: Bool?)   // `true`: windows of its kind tile; nil: nothing learned
    case askAgain(after: Double)
}

/// What a new window's resizable axes mean: one that takes no size change
/// yet (an opening animation, Ghostty setting up) is asked again after each
/// of `waits` (seconds since the first ask), then tiles; the size check
/// floats it if it still refuses.
public func probeStep(
    width: Bool,
    height: Bool,
    attempt: Int,
    waits: [Double]
) -> ProbeStep {
    if width != height { return .float }
    if !width, attempt < waits.count { return .askAgain(after: waits[attempt] - (attempt > 0 ? waits[attempt - 1] : 0)) }
    return .tile(learned: width ? true : nil)
}

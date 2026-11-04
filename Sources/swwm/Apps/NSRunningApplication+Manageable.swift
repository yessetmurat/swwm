//
//  NSRunningApplication+Manageable.swift
//  swwm
//
//  Created by Yesset Murat on 04.11.2026.
//

import AppKit
import os
import SwwmCore

extension NSRunningApplication {

    /// Apps whose windows swwm manages: regular apps, and menu-bar (accessory)
    /// apps that open windows, such as 1Password. Not macOS's own accessory
    /// agents (the Touch ID and password prompts of coreautha and
    /// SecurityAgent, Notification Center), not background agents, not swwm.
    var isManageable: Bool {
        guard processIdentifier != getpid() else { return false }
        switch activationPolicy {
        case .regular: return true
        case .accessory: return bundleURL.map { !$0.path.hasPrefix("/System/") } ?? false
        default: return false
        }
    }
}

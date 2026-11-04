//
//  Notice.swift
//  swwm
//
//  Created by Yesset Murat on 04.11.2026.
//

import AppKit

/// A non-modal alert: a modal one would block the event tap and freeze
/// input. The caller keeps the alert while it is on screen.
enum Notice {

    static func show(title: String, message: String) -> NSAlert {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = message
        a.addButton(withTitle: "OK")
        a.buttons[0].target = a.window
        a.buttons[0].action = #selector(NSWindow.orderOut(_:))
        a.layout()
        a.window.level = .floating
        a.window.center()
        a.window.orderFrontRegardless()
        return a
    }
}

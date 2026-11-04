//
//  AXUIElement+Attribute.swift
//  swwm
//
//  Created by Yesset Murat on 03.11.2026.
//

import AppKit
import ApplicationServices
import SwwmCore

/// Private but stable: maps an AX window element to its CGWindowID.
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

extension AXUIElement {

    func attribute<T>(_ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success else { return nil }
        return value as? T
    }
}

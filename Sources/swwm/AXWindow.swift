//
//  AXWindow.swift
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

/// A window of another app, driven through the Accessibility API.
/// Coordinates are global with a top-left origin.
struct AXWindow {

    let element: AXUIElement
    let pid: pid_t
    let id: WindowID
    let appName: String

    init?(_ element: AXUIElement, app: NSRunningApplication) {
        var id: CGWindowID = 0
        guard _AXUIElementGetWindow(element, &id) == .success, id != 0 else { return nil }
        self.element = element
        self.pid = app.processIdentifier
        self.id = id
        self.appName = app.localizedName ?? ""
    }

    static func windows(of app: NSRunningApplication) -> [AXWindow] {
        let el = AXUIElementCreateApplication(app.processIdentifier)
        let list: [AXUIElement] = el.attribute(kAXWindowsAttribute) ?? []
        return list.compactMap { AXWindow($0, app: app) }
    }

    var title: String { element.attribute(kAXTitleAttribute) ?? "" }
    var isMinimized: Bool { element.attribute(kAXMinimizedAttribute) ?? false }
    var isFullScreen: Bool { element.attribute("AXFullScreen") ?? false }

    var isStandard: Bool {
        element.attribute(kAXRoleAttribute) == kAXWindowRole as String
            && element.attribute(kAXSubroleAttribute) == kAXStandardWindowSubrole as String
    }

    var isResizable: Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, kAXSizeAttribute as CFString, &settable) == .success
            && settable.boolValue
    }

    var frame: CGRect {
        var origin = CGPoint.zero, size = CGSize.zero
        if let v: AXValue = element.attribute(kAXPositionAttribute) { AXValueGetValue(v, .cgPoint, &origin) }
        if let v: AXValue = element.attribute(kAXSizeAttribute) { AXValueGetValue(v, .cgSize, &size) }
        return CGRect(origin: origin, size: size)
    }

    func setPosition(_ p: CGPoint) {
        withoutEnhancedUI { position(p) }
    }

    /// Position, size, then position again: some apps clamp the size against
    /// the old position. Applied once; an app that refuses a size keeps its own.
    func setFrame(_ r: CGRect) {
        withoutEnhancedUI {
            var size = r.size
            position(r.origin)
            AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &size)!)
            position(r.origin)
        }
    }

    private func position(_ p: CGPoint) {
        var p = p
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &p)!)
    }

    /// With AXEnhancedUserInterface on (set by assistive apps), browsers
    /// animate frame changes and drop the ones that arrive mid-animation.
    /// Turned off for the change and restored, as yabai and AeroSpace do.
    private func withoutEnhancedUI(_ body: () -> Void) {
        let app = AXUIElementCreateApplication(pid)
        let key = "AXEnhancedUserInterface" as CFString
        let on: Bool = app.attribute(key as String) ?? false
        if on { AXUIElementSetAttributeValue(app, key, kCFBooleanFalse) }
        body()
        if on { AXUIElementSetAttributeValue(app, key, kCFBooleanTrue) }
    }

    func raise() {
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }

    func focus() {
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        raise()
        NSRunningApplication(processIdentifier: pid)?.activate()
    }
}

extension AXUIElement {

    func attribute<T>(_ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success else { return nil }
        return value as? T
    }
}

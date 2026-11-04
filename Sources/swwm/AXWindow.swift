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

/// What decides whether swwm manages a window, read in one go: for windows
/// an app reports, on the AX thread, as the app may be too busy to answer
/// right then.
struct WindowFacts {

    let role: String?
    let subrole: String?
    let isFullScreen: Bool
    let isMinimized: Bool

    init(_ w: AXWindow) {
        role = w.element.attribute(kAXRoleAttribute)
        subrole = w.element.attribute(kAXSubroleAttribute)
        isFullScreen = w.isFullScreen
        isMinimized = w.isMinimized
    }

    var isStandard: Bool { role == kAXWindowRole as String && subrole == kAXStandardWindowSubrole as String }
}

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

    /// Window server level: 0 for normal windows. System prompts (SecurityAgent
    /// sits at 1000), floating panels and overlays are above and never tiled.
    var level: Int { WindowServer.window(id)?.layer ?? 0 }

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

    /// True when the app took the write.
    @discardableResult
    func setPosition(_ p: CGPoint) -> Bool {
        var ok = false
        withoutEnhancedUI { ok = position(p) }
        return ok
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

    /// Which axes take a new size, found in place by asking for one point
    /// more (one less where that fails, as at a maximum) and putting it back.
    func resizableAxes() -> (width: Bool, height: Bool) {
        var axes = (width: false, height: false)
        withoutEnhancedUI {
            let s = frame.size
            func size(_ w: CGFloat, _ h: CGFloat) -> CGSize {
                var v = CGSize(width: w, height: h)
                AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &v)!)
                return frame.size
            }
            var t = size(s.width + 1, s.height + 1)
            axes = (t.width != s.width, t.height != s.height)
            if !axes.width || !axes.height {
                t = size(axes.width ? t.width : s.width - 1, axes.height ? t.height : s.height - 1)
                axes = (axes.width || t.width != s.width, axes.height || t.height != s.height)
            }
            _ = size(s.width, s.height)
        }
        return axes
    }

    @discardableResult
    private func position(_ p: CGPoint) -> Bool {
        var p = p
        return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &p)!) == .success
    }

    /// With AXEnhancedUserInterface on (set by assistive apps), browsers
    /// animate frame changes and drop the ones that arrive mid-animation.
    /// Turned off for the change and restored.
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

//
//  AppWindow.swift
//  SwwmCore
//
//  Created by Yesset Murat on 04.11.2026.
//

import CoreGraphics

/// What swwm knows of another app's window, read in one go on that app's
/// queue: decisions work from this, never from the app itself.
public struct AppWindow: Equatable, Sendable {

    public let id: WindowID
    public let pid: Int32
    public let app: String
    public let title: String
    public let frame: CGRect
    public let layer: Int
    public let role: String?
    public let subrole: String?
    public let isFullScreen: Bool
    public let isMinimized: Bool
    public let isResizable: Bool          // the size attribute is settable
    public let hasFullScreenButton: Bool  // tells an app's main windows from its panels
    public let listed: Set<WindowID>      // the app's listed windows when this was read

    public init(
        id: WindowID,
        pid: Int32,
        app: String,
        title: String,
        frame: CGRect,
        layer: Int,
        role: String?,
        subrole: String?,
        isFullScreen: Bool,
        isMinimized: Bool,
        isResizable: Bool,
        hasFullScreenButton: Bool,
        listed: Set<WindowID>
    ) {
        self.id = id
        self.pid = pid
        self.app = app
        self.title = title
        self.frame = frame
        self.layer = layer
        self.role = role
        self.subrole = subrole
        self.isFullScreen = isFullScreen
        self.isMinimized = isMinimized
        self.isResizable = isResizable
        self.hasFullScreenButton = hasFullScreenButton
        self.listed = listed
    }

    public var isStandard: Bool { role == "AXWindow" && subrole == "AXStandardWindow" }

    /// Finder lists its desktop as a scroll area.
    public var isFinderDesktop: Bool { role == "AXScrollArea" }
}

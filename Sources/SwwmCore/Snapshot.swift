//
//  Snapshot.swift
//  SwwmCore
//
//  Created by Yesset Murat on 03.11.2026.
//

import CoreGraphics
import Foundation

/// What the app layer knows about a window and the World does not.
public struct WindowInfo: Sendable {

    public var app: String
    public var title: String
    public var frame: CGRect

    public init(app: String, title: String, frame: CGRect) {
        self.app = app
        self.title = title
        self.frame = frame
    }
}

public struct Frame: Codable, Equatable, Sendable {

    public var x, y, width, height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        (self.x, self.y, self.width, self.height) = (x, y, width, height)
    }

    init(_ r: CGRect) { self.init(x: r.minX, y: r.minY, width: r.width, height: r.height) }
}

public struct WindowSnapshot: Codable, Equatable, Sendable {

    public var id: WindowID
    public var app: String
    public var title: String
    public var workspace: String
    public var monitor: MonitorID
    public var floating: Bool
    public var zoomed: Bool
    public var visible: Bool
    public var focused: Bool
    public var frame: Frame
}

public struct WorkspaceSnapshot: Codable, Equatable, Sendable {

    public var name: String
    public var monitor: MonitorID
    public var active: Bool
    public var windows: [WindowID]  // tiled in tree order, then floating
}

public struct MonitorSnapshot: Codable, Equatable, Sendable {

    public var id: MonitorID
    public var name: String
    public var builtin: Bool
    public var frame: Frame
    public var workspaces: [String]
    public var active: String?
    public var focused: Bool
}

extension World {

    /// Monitor order, then workspace order, then window order. Windows
    /// without `info` (already gone) are skipped.
    public func windowSnapshots(focused: WindowID?, info: (WindowID) -> WindowInfo?) -> [WindowSnapshot] {
        workspaceSnapshots().flatMap { ws in
            ws.windows.compactMap { id -> WindowSnapshot? in
                guard let i = info(id), let w = workspace(named: ws.name) else { return nil }
                return WindowSnapshot(id: id, app: i.app, title: i.title, workspace: ws.name, monitor: ws.monitor,
                                      floating: w.floating[id] != nil, zoomed: w.zoomed == id, visible: ws.active,
                                      focused: id == focused, frame: Frame(i.frame))
            }
        }
    }

    public func workspaceSnapshots() -> [WorkspaceSnapshot] {
        monitors.flatMap { m in
            workspaces(on: m.id).compactMap { name in
                workspace(named: name).map {
                    WorkspaceSnapshot(name: name, monitor: m.id, active: activeWorkspace(on: m.id) == name, windows: $0.windows)
                }
            }
        }
    }

    public func monitorSnapshots(focusedMonitor: MonitorID?) -> [MonitorSnapshot] {
        monitors.map { m in
            MonitorSnapshot(id: m.id, name: m.name, builtin: m.isBuiltin, frame: Frame(m.frame),
                            workspaces: workspaces(on: m.id), active: activeWorkspace(on: m.id), focused: m.id == focusedMonitor)
        }
    }
}

/// Pretty-printed JSON with sorted keys, for people and `jq` alike.
public func json<T: Encodable>(_ value: T) -> String {
    let e = JSONEncoder()
    e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return (try? e.encode(value)).map { String(decoding: $0, as: UTF8.self) } ?? "null"
}

//
//  BarController.swift
//  swwm
//
//  Created by Yesset Murat on 03.11.2026.
//

import AppKit
import SwwmCore

/// One bar panel per display, redrawn at most once per run-loop turn.
final class BarController {

    private let manager: Manager
    private var panels: [MonitorID: BarPanel] = [:]
    private var status = Status(language: nil, clock: clockText(Date()), battery: nil, volume: nil)
    private var scheduled = false
    private var steppedAside: Set<MonitorID> = []
    private var rendered: [MonitorID: (BarState, Status, BarStyle)] = [:]  // what each panel shows

    init(manager: Manager) {
        self.manager = manager
    }

    /// Matches panels to the connected displays and their frames.
    func rebuild() {
        rendered = [:]
        let monitors = manager.world.monitors
        for (id, panel) in panels where !monitors.contains(where: { $0.id == id }) {
            panel.close()
            panels[id] = nil
        }
        let height = manager.world.config.settings.barHeight
        for m in monitors {
            let frame = Displays.appKitRect(CGRect(x: m.frame.minX, y: m.frame.minY, width: m.frame.width, height: height))
            if let panel = panels[m.id] {
                panel.setFrame(frame, display: false)
            } else {
                panels[m.id] = BarPanel(frame: frame)
            }
        }
        redraw()
    }

    /// Hides the bar of a display while the macOS menu bar is revealed there.
    func cursorMoved(_ p: CGPoint) {
        let height = manager.world.config.settings.barHeight
        for m in manager.world.monitors {
            let was = steppedAside.contains(m.id)
            let now = barHidden(cursor: p, display: m.frame, barHeight: height, hidden: was)
            guard now != was, let panel = panels[m.id] else { continue }
            if now { steppedAside.insert(m.id) } else { steppedAside.remove(m.id) }
            panel.fade(visible: !now)
        }
    }

    func setNeedsUpdate() {
        guard !scheduled else { return }
        scheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.scheduled = false
            self?.redraw()
        }
    }

    func update(status: Status) {
        guard status != self.status else { return }
        self.status = status
        setNeedsUpdate()
    }

    private func redraw() {
        let world = manager.world
        for m in world.monitors {
            let state = world.barState(on: m.id, focused: manager.focused) { [manager] in manager.appName(of: $0) }
            let style = world.config.bar
            // Only when something it shows changed: focus moves often, a redraw builds every item.
            if let r = rendered[m.id], r.0 == state, r.1 == status, r.2 == style { continue }
            rendered[m.id] = (state, status, style)
            panels[m.id]?.render(state, status, style: style) { [manager] in manager.show($0) }
        }
    }
}

//
//  BarController.swift
//  swwm
//
//  Created by Yesset Murat on 03.11.2026.
//

import AppKit
import SwwmCore

/// The right side of the bar: system state, the same on every display.
struct Status: Equatable {

    var language: String?
    var clock: String
    var battery: IndicatorItem?
    var volume: IndicatorItem?
}

/// One bar panel per display, redrawn at most once per run-loop turn.
final class BarController {

    private let manager: Manager
    private var panels: [MonitorID: BarPanel] = [:]
    private var status = Status(language: nil, clock: clockText(Date()), battery: nil, volume: nil)
    private var scheduled = false
    private var steppedAside: Set<MonitorID> = []

    init(manager: Manager) {
        self.manager = manager
    }

    /// Matches panels to the connected displays and their frames.
    func rebuild() {
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
            panels[m.id]?.render(state, status, style: world.config.bar) { [manager] in manager.show($0) }
        }
    }
}

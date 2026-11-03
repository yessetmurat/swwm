//
//  main.swift
//  swwm
//
//  Created by Yesset Murat on 03.11.2026.
//

import AppKit
import ServiceManagement
import SwwmCore

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var manager: Manager?
    private var observer: AppObserver?
    private var tap: EventTap?
    private var bar: BarController?
    private var status: SystemStatus?
    private var loader: ConfigLoader?
    private var signals: [DispatchSourceSignal] = []
    private var displayChange: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let prompt = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        if AXIsProcessTrustedWithOptions(prompt) {
            start()
        } else {
            // Wait for the user to grant Accessibility; no restart needed.
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
                guard AXIsProcessTrusted() else { return }
                timer.invalidate()
                self?.start()
            }
        }
    }

    private func start() {
        // A hung app must not stall swwm (and the event tap) for the 6 s default.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.25)
        Fonts.registerBundled()
        var apply: (Config) -> Void = { _ in }
        let loader = ConfigLoader { apply($0) }
        let config = loader.load()
        let manager = Manager(world: World(config: config))
        let tap = EventTap(manager: manager)
        let observer = AppObserver(manager: manager)
        let bar = BarController(manager: manager)
        apply = { config in
            manager.world.apply(config: config)
            tap.update(config: config)
            manager.layoutAll()
            bar.rebuild()
        }
        manager.onChange = { bar.setNeedsUpdate() }
        tap.onMouseMoved = { bar.cursorMoved($0) }
        manager.onReload = { loader.reload() }
        manager.onQuit = { NSApp.terminate(nil) }

        tap.update(config: config)
        manager.start()
        bar.rebuild()
        let status = SystemStatus { bar.update(status: $0) }
        status.start()
        self.status = status
        observer.start()
        tap.start()
        loader.start()
        (self.manager, self.tap, self.observer, self.loader, self.bar) = (manager, tap, observer, loader, bar)

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.displayChange?.cancel()
            let item = DispatchWorkItem {
                manager.displaysChanged()
                bar.rebuild()
            }
            self?.displayChange = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
        }

        for sig in [SIGINT, SIGTERM] {
            signal(sig, SIG_IGN)
            let s = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            s.setEventHandler { NSApp.terminate(nil) }
            s.resume()
            signals.append(s)
        }

        if SMAppService.mainApp.status != .enabled {
            do { try SMAppService.mainApp.register() } catch { NSLog("swwm: login item: \(error)") }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        manager?.restoreAll()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

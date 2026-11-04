//
//  main.swift
//  swwm
//
//  Created by Yesset Murat on 03.11.2026.
//

import AppKit
import SwwmCore

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var manager: Manager?
    private var observer: AppObserver?
    private var tap: EventTap?
    private var bar: BarController?
    private var status: SystemStatus?
    private var server: CommandServer?
    private var shadowAlert: NSAlert?
    private var loader: ConfigLoader?
    private var signals: [DispatchSourceSignal] = []
    private var displayChange: DispatchWorkItem?
    private var dockWatch: NSKeyValueObservation?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Up before the Accessibility wait, so the CLI and a second launch see swwm.
        let server = CommandServer { [weak self] request in
            self?.manager?.handle(request) ?? .error("waiting for Accessibility permission")
        }
        server.start()
        self.server = server
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
            manager.applyShadowAll()
            bar.rebuild()
        }
        manager.dockModuleInstalled = DockModuleInstaller.isInstalled
        manager.onShadowUnavailable = { [weak self] in
            self?.notify("Window shadows are unavailable: the Dock module did not answer. "
                + "See \(DockModuleInstaller.logPath).")
        }
        manager.onLevelUnavailable = { [weak self] in
            self?.notify("Floating windows on top need the updated Dock module: "
                + "run `sudo swwm --install-dock-module`, then `killall Dock`.")
        }
        manager.onChange = { bar.setNeedsUpdate() }
        tap.onMouseMoved = { bar.cursorMoved($0) }
        manager.onReload = { loader.reload() }
        manager.onQuit = { NSApp.terminate(nil) }

        tap.update(config: config)
        WindowServer.start { manager.serverEvent($0) }
        manager.start()
        bar.rebuild()
        let status = SystemStatus { bar.update(status: $0) }
        status.start()
        self.status = status
        // A new Dock drops the shadows; its payload comes up a few seconds later.
        // Dock is not a regular app: no launch notification, only this list.
        dockWatch = NSWorkspace.shared.observe(\.runningApplications, options: [.new]) { _, change in
            guard change.newValue?.contains(where: { $0.bundleIdentifier == "com.apple.dock" }) == true else { return }
            DispatchQueue.main.async {
                manager.dock.whenReachable {
                    manager.applyShadowAll()
                    manager.applyLevelAll()  // windows an older payload turned down, after a re-install
                }
            }
        }

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
    }

    /// A non-modal panel (a modal one would block the event tap).
    private func notify(_ message: String) {
        let a = NSAlert()
        a.messageText = "swwm"
        a.informativeText = message
        a.addButton(withTitle: "OK")
        a.buttons[0].target = a.window
        a.buttons[0].action = #selector(NSWindow.orderOut(_:))
        a.layout()
        a.window.level = .floating
        a.window.center()
        a.window.orderFrontRegardless()
        shadowAlert = a
    }

    func applicationWillTerminate(_ notification: Notification) {
        server?.stop()
        manager?.restoreAll()
    }
}

// With arguments this binary is the CLI; without, the window manager.
let cliArgs = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-psn_") }
switch cliArgs.first {
case "--install-dock-module": DockModuleInstaller.install()
case "--uninstall-dock-module": DockModuleInstaller.uninstall()
default: break
}
if !cliArgs.isEmpty { Client.run(Array(cliArgs)) }
if Client.isRunning() {
    FileHandle.standardError.write(Data("swwm is already running\n".utf8))
    exit(1)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

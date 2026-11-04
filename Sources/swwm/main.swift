//
//  main.swift
//  swwm
//
//  Created by Yesset Murat on 03.11.2026.
//

import AppKit
import SwwmCore

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

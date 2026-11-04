//
//  DockModuleInstaller.swift
//  swwm
//
//  Created by Yesset Murat on 03.11.2026.
//

import Foundation

/// Installs the optional Dock module: a root launchd daemon that loads the
/// Dock payload at boot and after every Dock restart. Run with sudo.
enum DockModuleInstaller {

    static let supportDir = "/Library/Application Support/swwm"
    static let plistPath = "/Library/LaunchDaemons/dev.swwm.dock.plist"
    static let logPath = "/Library/Logs/swwm-dock.log"
    static let label = "dev.swwm.dock"

    static var isInstalled: Bool { FileManager.default.fileExists(atPath: plistPath) }

    static func install() -> Never {
        requireRoot()
        checkSystem()

        let osax = sourceDir()
        let loader = osax + "/loader", payload = osax + "/payload"
        for f in [loader, payload] where !FileManager.default.fileExists(atPath: f) {
            die("missing \(f); build with `make dev` first", 1)
        }

        // Root-owned copies: the daemon must never run a file under a
        // user-writable directory.
        run("/bin/rm", "-rf", supportDir)
        run("/bin/mkdir", "-p", supportDir)
        run(
            "/bin/cp",
            loader,
            payload,
            supportDir
        )
        run(
            "/usr/sbin/chown",
            "-R",
            "root:wheel",
            supportDir
        )
        run(
            "/bin/chmod",
            "-R",
            "755",
            supportDir
        )

        let installedLoader = supportDir + "/loader"
        let installedPayload = supportDir + "/payload"
        try? plist(loader: installedLoader, payload: installedPayload).write(toFile: plistPath, atomically: true, encoding: .utf8)
        run("/usr/sbin/chown", "root:wheel", plistPath)
        run("/bin/chmod", "644", plistPath)

        _ = runStatus("/bin/launchctl", "bootout", "system/\(label)")  // ignore "not loaded"
        let bootstrapped = runStatus(
            "/bin/launchctl",
            "bootstrap",
            "system",
            plistPath
        )
        if bootstrapped != 0 {
            die("launchctl bootstrap failed", 1)
        }

        print("Dock module installed. It loads into Dock at boot and after each Dock restart (killall Dock to load it now).")
        exit(0)
    }

    static func uninstall() -> Never {
        requireRoot()
        _ = runStatus("/bin/launchctl", "bootout", "system/\(label)")
        run("/bin/rm", "-f", plistPath)
        run("/bin/rm", "-rf", supportDir)

        print("Dock module removed. Dock keeps the payload until it restarts (killall Dock to unload now).")
        exit(0)
    }

    // MARK: - Checks

    private static func requireRoot() {
        if getuid() != 0 { die("run with sudo", 64) }
    }

    /// The module needs SIP partly disabled and the arm64e preview ABI.
    private static func checkSystem() {
        let sip = output("/usr/bin/csrutil", "status")
        var missing: [String] = []
        if !sip.contains("Filesystem Protections: disabled") { missing.append("SIP filesystem protections") }
        if !sip.contains("Debugging Restrictions: disabled") { missing.append("SIP debugging restrictions") }
        if !output("/usr/sbin/nvram", "boot-args").contains("-arm64e_preview_abi") {
            missing.append("the -arm64e_preview_abi boot-arg")
        }

        guard missing.isEmpty else {
            die("""
                the Dock module needs \(missing.joined(separator: ", ")) to be set.
                From Recovery (csrutil needs Recovery; the boot-arg needs `sudo nvram boot-args=-arm64e_preview_abi`):
                  csrutil enable --without fs --without debug --without nvram
                Then reboot and run this again.
                """, 1)
        }
    }

    private static func sourceDir() -> String {
        // Not argv[0]: run from PATH it is a bare `swwm`, not a path.
        guard let exe = Bundle.main.executableURL?.resolvingSymlinksInPath() else {
            die("cannot find the swwm binary", 1)
        }

        return exe.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("share/swwm/osax").path
    }

    private static func plist(loader: String, payload: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \t<key>Label</key>
        \t<string>\(label)</string>
        \t<key>ProgramArguments</key>
        \t<array>
        \t\t<string>\(loader)</string>
        \t\t<string>--watch</string>
        \t\t<string>\(payload)</string>
        \t</array>
        \t<key>RunAtLoad</key>
        \t<true/>
        \t<key>KeepAlive</key>
        \t<true/>
        \t<key>StandardErrorPath</key>
        \t<string>\(logPath)</string>
        </dict>
        </plist>
        """
    }

    // MARK: - Process helpers

    @discardableResult
    private static func runStatus(_ path: String, _ args: String...) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        try? p.run()
        p.waitUntilExit()

        return p.terminationStatus
    }

    private static func run(_ path: String, _ args: String...) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        try? p.run()
        p.waitUntilExit()

        if p.terminationStatus != 0 { die("\(path) \(args.joined(separator: " ")) failed", 1) }
    }

    private static func output(_ path: String, _ args: String...) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe

        try? p.run()
        p.waitUntilExit()

        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }

    private static func die(_ message: String, _ code: Int32) -> Never {
        FileHandle.standardError.write(Data(("swwm: " + message + "\n").utf8))
        exit(code)
    }
}

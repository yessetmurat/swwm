//
//  ConfigLoader.swift
//  swwm
//
//  Created by Yesset Murat on 03.11.2026.
//

import AppKit
import SwwmCore

/// Reads ~/.config/swwm/swwm.toml (creating it on first launch) and re-reads
/// it on save. A bad config is reported and the running one stays.
final class ConfigLoader {

    static let directory = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/swwm")
    static let file = directory.appending(path: "swwm.toml")

    private let onChange: (Config) -> Void
    private var stream: FSEventStreamRef?
    private var pending: DispatchWorkItem?
    private var lastText: String?
    private var shownError: String?
    private var alert: NSAlert?

    init(onChange: @escaping (Config) -> Void) {
        self.onChange = onChange
    }

    /// The config to start with: the file's, or the default when it is broken.
    func load() -> Config {
        let fm = FileManager.default

        if !fm.fileExists(atPath: Self.file.path) {
            try? fm.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            try? Config.defaultTOML.write(to: Self.file, atomically: true, encoding: .utf8)
        }

        return read() ?? .default
    }

    /// FSEvents with file events: sees both in-place writes (vim, nano) and
    /// atomic replaces; a directory vnode watch misses the former.
    func start() {
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)

        guard let s = FSEventStreamCreate(
            nil,
            { _, info, _, _, _, _ in
            guard let info else {
                return
            }
            Unmanaged<ConfigLoader>.fromOpaque(info).takeUnretainedValue().scheduleReload()
        },
            &context,
            [Self.directory.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.1,
            flags
        )
        else {
                return
            }

        FSEventStreamSetDispatchQueue(s, .main)
        FSEventStreamStart(s)
        stream = s
    }

    /// Re-reads the file; returns the error message when it is not applied.
    @discardableResult
    func reload() -> String? {
        guard let c = read() else {
            return shownError ?? "cannot read \(Self.file.path)"
        }
        onChange(c)
        return nil
    }

    private func scheduleReload() {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.reloadIfChanged() }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: item)
    }

    private func reloadIfChanged() {
        let text = try? String(contentsOf: Self.file, encoding: .utf8)
        guard text != lastText else {
            return
        }
        reload()
    }

    private func read() -> Config? {
        guard let text = try? String(contentsOf: Self.file, encoding: .utf8) else {
            show("cannot read \(Self.file.path)")
            return nil
        }

        lastText = text
        do {
            let c = try Config.parse(text)
            log.debug("config read: gap=\(c.settings.gap, privacy: .public)")
            shownError = nil
            alert?.window.orderOut(nil)

            return c
        } catch {
            show(error.message)
            return nil
        }
    }

    private func show(_ message: String) {
        guard message != shownError else {
            return
        }

        shownError = message
        alert?.window.orderOut(nil)
        alert = Notice.show(title: "swwm: config error", message: message + "\n\nThe previous config stays active.")
    }
}

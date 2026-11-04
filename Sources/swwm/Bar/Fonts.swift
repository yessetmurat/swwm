//
//  Fonts.swift
//  swwm
//
//  Created by Yesset Murat on 03.11.2026.
//

import AppKit
import SwwmCore

/// The bar's fonts ship inside the app; nothing has to be installed.
enum Fonts {

    /// Fonts live in `share/swwm/fonts` next to `bin/` (Homebrew's layout and
    /// `make dev`'s); the executable may be reached through a symlink.
    static func registerBundled() {
        guard let exe = Bundle.main.executableURL?.resolvingSymlinksInPath(),
              case let dir = exe.deletingLastPathComponent().deletingLastPathComponent().appending(path: "share/swwm/fonts"),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return
        }

        for url in files where url.pathExtension == "ttf" {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    /// Finds the face by family and style name (PostScript names differ:
    /// "SemiBold" is IBMPlexMono-SmBld); falls back to a semibold system font.
    static func font(_ spec: FontSpec) -> NSFont {
        if let font = cache[spec] { return font }

        let font = lookUp(spec)
        cache[spec] = font
        return font
    }

    /// Looked up once per spec: the bar asks on every redraw. Main thread.
    nonisolated(unsafe) private static var cache: [FontSpec: NSFont] = [:]

    private static func lookUp(_ spec: FontSpec) -> NSFont {
        let size = CGFloat(spec.size)
        let members = NSFontManager.shared.availableMembers(ofFontFamily: spec.family) ?? []

        if let member = members.first(where: { ($0[1] as? String)?.caseInsensitiveCompare(spec.style) == .orderedSame }),
           let name = member[0] as? String, let font = NSFont(name: name, size: size) {
            return font
        }

        return spec.family.localizedCaseInsensitiveContains("mono")
            ? .monospacedSystemFont(ofSize: size, weight: .semibold)
            : .systemFont(ofSize: size, weight: .semibold)
    }
}

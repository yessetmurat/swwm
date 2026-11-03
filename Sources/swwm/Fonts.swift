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

    static func registerBundled() {
        guard let dir = Bundle.main.resourceURL?.appending(path: "Fonts"),
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

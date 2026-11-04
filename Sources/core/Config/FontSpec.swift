//
//  FontSpec.swift
//  SwwmCore
//
//  Created by Yesset Murat on 03.11.2026.
//

import Foundation
import TOMLKit

/// A font as "Family:Style:Size", e.g. "IBM Plex Mono:SemiBold:15".
public struct FontSpec: Hashable, Sendable {

    public var family: String
    public var style: String
    public var size: Double

    public init(family: String, style: String, size: Double) {
        self.family = family
        self.style = style
        self.size = size
    }

    public static func parse(_ s: String) throws(ConfigError) -> FontSpec {
        let parts = s.split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 3,
              !parts[0].isEmpty,
              !parts[1].isEmpty,
              let size = Double(parts[2]),
              size > 0 else {
            throw ConfigError("font '\(s)' must be \"Family:Style:Size\"")
        }
        return FontSpec(family: parts[0], style: parts[1], size: size)
    }
}

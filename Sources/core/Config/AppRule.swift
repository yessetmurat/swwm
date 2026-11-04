//
//  AppRule.swift
//  SwwmCore
//
//  Created by Yesset Murat on 03.11.2026.
//

import Foundation

public struct AppRule: @unchecked Sendable {  // NSRegularExpression is immutable

    public var app: String
    public var title: String?
    public var workspace: String?
    public var float: Bool?
    let appRegex: NSRegularExpression
    let titleRegex: NSRegularExpression?

    public func matches(app: String, title: String) -> Bool {
        Self.search(appRegex, app) && (titleRegex.map { Self.search($0, title) } ?? true)
    }

    static func search(_ r: NSRegularExpression, _ s: String) -> Bool {
        r.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }
}

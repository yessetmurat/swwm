//
//  MonitorRule.swift
//  SwwmCore
//
//  Created by Yesset Murat on 03.11.2026.
//

import Foundation
import TOMLKit

public struct MonitorRule: Equatable, Sendable {

    public var match: String
    public var workspaces: [String]
}

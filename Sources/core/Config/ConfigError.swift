//
//  ConfigError.swift
//  SwwmCore
//
//  Created by Yesset Murat on 03.11.2026.
//

import Foundation
import TOMLKit

public struct ConfigError: Error, Equatable, Sendable {

    public let message: String
    public init(_ message: String) { self.message = message }
}

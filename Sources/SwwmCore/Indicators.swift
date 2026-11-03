//
//  Indicators.swift
//  SwwmCore
//
//  Created by Yesset Murat on 03.11.2026.
//

import Foundation

public struct IndicatorItem: Equatable, Sendable {

    public var symbol: String  // SF Symbol name
    public var text: String

    public init(symbol: String, text: String) {
        self.symbol = symbol
        self.text = text
    }
}

/// strftime `%a %d %b %I:%M %p` in the POSIX locale: `Tue 03 Nov 09:54 AM`.
public func clockText(_ date: Date, timeZone: TimeZone = .current) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = timeZone
    f.dateFormat = "EEE dd MMM hh:mm a"
    return f.string(from: date)
}

/// nil percent (no battery) hides the item.
public func batteryItem(percent: Int?, onAC: Bool) -> IndicatorItem? {
    guard let p = percent else { return nil }
    let symbol: String
    switch p {
    case _ where onAC: symbol = "battery.100percent.bolt"
    case 90...: symbol = "battery.100percent"
    case 60..<90: symbol = "battery.75percent"
    case 30..<60: symbol = "battery.50percent"
    case 10..<30: symbol = "battery.25percent"
    default: symbol = "battery.0percent"
    }
    return IndicatorItem(symbol: symbol, text: "\(p)%")
}

/// `volume` is 0...1; nil (no volume control on the device) hides the item.
public func volumeItem(volume: Float?, muted: Bool) -> IndicatorItem? {
    guard let v = volume else { return nil }
    let p = muted ? 0 : Int((v * 100).rounded())  // muted reads as 0%, as sketchybar showed it
    let symbol: String
    switch p {
    case _ where muted: symbol = "speaker.slash.fill"
    case 60...: symbol = "speaker.wave.3.fill"
    case 30..<60: symbol = "speaker.wave.2.fill"
    case 1..<30: symbol = "speaker.wave.1.fill"
    default: symbol = "speaker.slash.fill"
    }
    return IndicatorItem(symbol: symbol, text: "\(p)%")
}

/// Two-letter label of a keyboard layout's primary (first) language.
public func languageLabel(_ languages: [String]) -> String? {
    guard let code = languages.first?.split(separator: "-").first, !code.isEmpty else { return nil }
    return code == "kk" ? "KZ" : code.uppercased()
}

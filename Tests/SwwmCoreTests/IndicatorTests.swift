//
//  IndicatorTests.swift
//  SwwmCoreTests
//
//  Created by Yesset Murat on 03.11.2026.
//

import Foundation
import Testing
@testable import SwwmCore

@Test func clockFormat() {
    let d = ISO8601DateFormatter().date(from: "2026-11-03T09:54:00Z")!
    let utc = TimeZone(identifier: "UTC")!

    #expect(clockText(d, timeZone: utc) == "Tue 03 Nov 09:54 AM")
    #expect(clockText(d.addingTimeInterval(4 * 3600), timeZone: utc) == "Tue 03 Nov 01:54 PM")
}

@Test func batteryLevels() {
    #expect(batteryItem(percent: 87, onAC: false) == IndicatorItem(symbol: "battery.75percent", text: "87%"))
    #expect(batteryItem(percent: 100, onAC: false)?.symbol == "battery.100percent")
    #expect(batteryItem(percent: 30, onAC: false)?.symbol == "battery.50percent")
    #expect(batteryItem(percent: 9, onAC: false)?.symbol == "battery.0percent")
    #expect(batteryItem(percent: 40, onAC: true)?.symbol == "battery.100percent.bolt")
}

@Test func batteryHiddenWithoutBattery() {
    #expect(batteryItem(percent: nil, onAC: true) == nil)
}

@Test func volumeLevels() {
    #expect(volumeItem(volume: 0.4, muted: false) == IndicatorItem(symbol: "speaker.wave.2.fill", text: "40%"))
    #expect(volumeItem(volume: 1, muted: false)?.symbol == "speaker.wave.3.fill")
    #expect(volumeItem(volume: 0.05, muted: false)?.symbol == "speaker.wave.1.fill")
    #expect(volumeItem(volume: 0, muted: false)?.symbol == "speaker.slash.fill")
    #expect(volumeItem(volume: 0.7, muted: true) == IndicatorItem(symbol: "speaker.slash.fill", text: "0%"))
}

@Test func volumeHiddenWithoutControl() {
    #expect(volumeItem(volume: nil, muted: false) == nil)
}

@Test func languageLabels() {
    #expect(languageLabel(["en", "acf", "af"]) == "EN")
    #expect(languageLabel(["kk", "be", "bg"]) == "KZ")
    #expect(languageLabel(["ru"]) == "RU")
    #expect(languageLabel(["de-CH"]) == "DE")
    #expect(languageLabel([]) == nil)
}

@Test func clockTicksOnTheNextWholeMinute() {
    let t = Date(timeIntervalSinceReferenceDate: 60 * 1000 + 30.2)

    #expect(nextMinute(after: t) == Date(timeIntervalSinceReferenceDate: 60 * 1001))
    #expect(nextMinute(after: Date(timeIntervalSinceReferenceDate: 60 * 1001)) == Date(timeIntervalSinceReferenceDate: 60 * 1002))
}

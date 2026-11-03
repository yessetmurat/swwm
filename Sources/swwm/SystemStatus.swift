//
//  SystemStatus.swift
//  swwm
//
//  Created by Yesset Murat on 03.11.2026.
//

import AppKit
import AudioToolbox
import Carbon
import CoreAudio
import IOKit.ps
import SwwmCore

/// Input language, clock, battery and volume for the bar. Everything but the
/// clock updates on system notifications, not by polling.
final class SystemStatus {

    private let onChange: (Status) -> Void
    private var status = Status(language: nil, clock: clockText(Date()), battery: nil, volume: nil)
    private var timer: Timer?
    private var device = AudioObjectID(kAudioObjectUnknown)
    private lazy var deviceListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.refreshVolume() }

    init(onChange: @escaping (Status) -> Void) {
        self.onChange = onChange
    }

    func start() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil, queue: .main
        ) { [weak self] _ in self?.refreshLanguage() }

        let t = Timer(fire: Date(timeIntervalSinceReferenceDate: Date.timeIntervalSinceReferenceDate.rounded(.up)),
                      interval: 1, repeats: true) { [weak self] _ in self?.refreshClock() }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            Unmanaged<SystemStatus>.fromOpaque(ctx).takeUnretainedValue().refreshBattery()
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refreshBattery() }

        var defaultOutput = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultOutput, .main) { [weak self] _, _ in
            self?.bindDevice()
        }
        bindDevice()

        refreshLanguage()
        refreshBattery()
    }

    // MARK: - Pieces

    private func publish(_ change: (inout Status) -> Void) {
        var s = status
        change(&s)
        guard s != status else { return }
        status = s
        onChange(s)
    }

    private func refreshClock() {
        publish { $0.clock = clockText(Date()) }
    }

    private func refreshLanguage() {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        let languages = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages)
            .map { Unmanaged<CFArray>.fromOpaque($0).takeUnretainedValue() as? [String] ?? [] } ?? []
        publish { $0.language = languageLabel(languages) }
    }

    private func refreshBattery() {
        var percent: Int?
        var onAC = false
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for ps in list {
                guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                      d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                      let current = d[kIOPSCurrentCapacityKey] as? Int,
                      let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
                percent = current * 100 / max
                onAC = d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            }
        }
        publish { $0.battery = batteryItem(percent: percent, onAC: onAC) }
    }

    /// Follows the default output device; listeners move with it.
    private func bindDevice() {
        var volume = Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput)
        var mute = Self.address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput)
        if device != kAudioObjectUnknown {
            AudioObjectRemovePropertyListenerBlock(device, &volume, .main, deviceListener)
            AudioObjectRemovePropertyListenerBlock(device, &mute, .main, deviceListener)
        }
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var defaultOutput = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &defaultOutput, 0, nil, &size, &id)
        device = id
        if device != kAudioObjectUnknown {
            AudioObjectAddPropertyListenerBlock(device, &volume, .main, deviceListener)
            AudioObjectAddPropertyListenerBlock(device, &mute, .main, deviceListener)
        }
        refreshVolume()
    }

    private func refreshVolume() {
        var volumeAddress = Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput)
        var muteAddress = Self.address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput)
        var volume: Float?
        var muted = false
        if device != kAudioObjectUnknown, AudioObjectHasProperty(device, &volumeAddress) {
            var v = Float32(0)
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(device, &volumeAddress, 0, nil, &size, &v) == noErr { volume = v }
            if AudioObjectHasProperty(device, &muteAddress) {
                var m = UInt32(0)
                size = UInt32(MemoryLayout<UInt32>.size)
                if AudioObjectGetPropertyData(device, &muteAddress, 0, nil, &size, &m) == noErr { muted = m != 0 }
            }
        }
        publish { $0.volume = volumeItem(volume: volume, muted: muted) }
    }

    private static func address(_ selector: AudioObjectPropertySelector,
                                _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
}

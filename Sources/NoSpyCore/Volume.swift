// Input volume read/write. Many input devices (USB displays, Bluetooth headsets)
// don't expose a software input volume to AppleScript — `get volume settings`
// returns "missing value" on them. So HAL is the primary path; AppleScript is
// kept as a fallback for the rare device where HAL has no volume property.
//
// `defaultInputDeviceID` is also used by Listening.swift; it's module-internal
// so both files share it without needing a public surface.

import Foundation
import CoreAudio

func defaultInputDeviceID() -> AudioDeviceID? {
    var id = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    let s = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                       &addr, 0, nil, &size, &id)
    return (s == noErr && id != 0) ? id : nil
}

/// Elements (channels) on the input scope that expose VolumeScalar.
/// Tries master (element 0); falls back to per-channel for devices without master.
private func inputVolumeElements(of device: AudioDeviceID) -> [UInt32] {
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyVolumeScalar,
        mScope: kAudioDevicePropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain)
    if AudioObjectHasProperty(device, &addr) {
        return [kAudioObjectPropertyElementMain]
    }
    var elems: [UInt32] = []
    for ch: UInt32 in 1...16 {
        addr.mElement = ch
        if AudioObjectHasProperty(device, &addr) { elems.append(ch) }
    }
    return elems
}

func halGetInputVolume() -> Int? {
    guard let device = defaultInputDeviceID() else { return nil }
    let elems = inputVolumeElements(of: device)
    guard !elems.isEmpty else { return nil }
    var sum: Float32 = 0
    var count: Float32 = 0
    for el in elems {
        var v: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: el)
        if AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &v) == noErr {
            sum += v
            count += 1
        }
    }
    guard count > 0 else { return nil }
    return Int((sum / count * 100).rounded())
}

func halSetInputVolume(_ target: Int) -> Bool {
    guard let device = defaultInputDeviceID() else { return false }
    let elems = inputVolumeElements(of: device)
    guard !elems.isEmpty else { return false }
    let scalar = max(0 as Float32, min(1, Float32(target) / 100.0))
    var anyOK = false
    for el in elems {
        var v = scalar
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: el)
        if AudioObjectSetPropertyData(device, &addr, 0, nil,
                                      UInt32(MemoryLayout<Float32>.size), &v) == noErr {
            anyOK = true
        }
    }
    return anyOK
}

public func getInputVolume() -> Int? {
    if let v = halGetInputVolume() { return v }
    let r = runAppleScript("input volume of (get volume settings)")
    if r.ok, let v = Int(r.stdout), (0...100).contains(v) { return v }
    if !r.ok { explainOsascriptFailure(r) }
    return nil
}

public func setInputVolume(_ target: Int) -> Bool {
    let clamped = max(0, min(100, target))
    if halSetInputVolume(clamped) { return true }
    let r = runAppleScript("set volume input volume \(clamped)")
    if !r.ok { explainOsascriptFailure(r) }
    return r.ok
}

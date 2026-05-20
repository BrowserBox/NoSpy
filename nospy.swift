// nospy.swift
// CLI tool to toggle macOS microphone input volume (mute/unmute default input)
// Checks for Siri/Assistant activity on mute → auto-opens settings pane if enabled
// Compile: swiftc nospy.swift -o nospy

import Foundation
import CoreAudio

// MARK: - Process helpers

struct ProcResult {
    let status: Int32
    let stdout: String
    let stderr: String
    var ok: Bool { status == 0 }
}

func runProcess(_ executable: String, _ args: [String]) -> ProcResult {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: executable)
    task.arguments = args
    let outPipe = Pipe(), errPipe = Pipe()
    task.standardOutput = outPipe
    task.standardError = errPipe
    do {
        try task.run()
        task.waitUntilExit()
    } catch {
        return ProcResult(status: -1, stdout: "", stderr: "\(error)")
    }
    let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(),
                     encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                     encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return ProcResult(status: task.terminationStatus, stdout: out, stderr: err)
}

func runAppleScript(_ script: String) -> ProcResult {
    runProcess("/usr/bin/osascript", ["-e", script])
}

func explainOsascriptFailure(_ r: ProcResult) {
    let s = r.stderr.lowercased()
    if s.contains("not authorized") || s.contains("not allowed") || s.contains("-1743") {
        print("⚠️ osascript was denied. Grant your terminal Automation access:")
        print("   System Settings → Privacy & Security → Automation → (your terminal) → System Events.")
    } else if !r.stderr.isEmpty {
        print("osascript: \(r.stderr)")
    }
}

// MARK: - CoreAudio HAL (input volume)
// Many input devices (USB displays, Bluetooth headsets) don't expose a software
// input volume to AppleScript — `get volume settings` returns "missing value".
// HAL works across that broader set of devices; it's the primary path. AppleScript
// is kept as a fallback for the rare device where HAL has no volume property.

private func defaultInputDeviceID() -> AudioDeviceID? {
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

// MARK: - Volume (HAL primary, AppleScript fallback)

func getInputVolume() -> Int? {
    if let v = halGetInputVolume() { return v }
    let r = runAppleScript("input volume of (get volume settings)")
    if r.ok, let v = Int(r.stdout), (0...100).contains(v) { return v }
    if !r.ok { explainOsascriptFailure(r) }
    return nil
}

func setInputVolume(_ target: Int) -> Bool {
    let clamped = max(0, min(100, target))
    if halSetInputVolume(clamped) { return true }
    let r = runAppleScript("set volume input volume \(clamped)")
    if !r.ok { explainOsascriptFailure(r) }
    return r.ok
}

// MARK: - Siri / Assistant

func isAssistantEnabled() -> Bool {
    let r = runProcess("/usr/bin/defaults",
                       ["read", "com.apple.assistant.support", "Assistant Enabled"])
    guard r.ok else { return false }
    let s = r.stdout.lowercased()
    return s == "1" || s == "true"
}

// MARK: - Settings deep links

func openSiriSettings() -> Bool {
    runProcess("/usr/bin/open",
               ["x-apple.systempreferences:com.apple.Siri-Settings.extension"]).ok
}

// MARK: - CLI dispatch

let args = CommandLine.arguments
let arg = args.count > 1 ? args[1].lowercased() : "toggle"

if arg == "--help" || arg == "-h" {
    print("nospy - quick mic mute toggle with Siri privacy check")
    print("Usage: nospy [toggle|on|off|status|siri]")
    print("  (no arg) = toggle mute/unmute")
    print("  on       = force mute")
    print("  off      = force unmute (to 80)")
    print("  status   = show current state + Siri note if relevant")
    print("  siri     = open System Settings → Siri pane")
    exit(0)
}

if arg == "siri" {
    if openSiriSettings() {
        print("Opened System Settings → Siri pane. Turn off 'Listen for “Siri”' or 'Hey Siri' for full mic privacy.")
    } else {
        print("Failed to open Siri settings. Go manually: System Settings > Apple Intelligence & Siri (or Siri & Spotlight).")
    }
    exit(0)
}

guard let current = getInputVolume() else {
    print("Failed to read current input volume")
    exit(1)
}

let target: Int
switch arg {
case "on", "mute":
    target = 0
case "off", "unmute":
    target = 80
case "status":
    let emoji = current == 0 ? "🔴 Muted" : "🟢 Live"
    print("\(emoji) (input volume: \(current))")

    if current == 0 && isAssistantEnabled() {
        print("⚠️ Note: System input is muted, but if 'Listen for “Siri”' is on, background wake-word may still work.")
        print("   Run 'nospy siri' to open the Siri settings pane and disable it easily.")
        print("   Or go to System Settings > Apple Intelligence & Siri (or Siri & Spotlight).")
    }
    exit(0)
default:  // toggle
    target = current == 0 ? 80 : 0
}

if setInputVolume(target) {
    let emoji = target == 0 ? "🔴 Muted" : "🟢 Unmuted"
    print("\(emoji) (set to \(target))")

    if target == 0 && isAssistantEnabled() {
        print("⚠️ Heads up: 'Hey Siri' / 'Listen for Siri' may still detect sound even when muted.")
        print("   Auto-opening System Settings → Siri pane for easy disable...")
        if !openSiriSettings() {
            print("   Failed to auto-open. Run 'nospy siri' or go manually: System Settings > Apple Intelligence & Siri.")
        }
    }
} else {
    print("Failed to set input volume")
    exit(1)
}

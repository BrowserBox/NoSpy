// nospy.swift
// CLI tool to toggle macOS microphone input volume (mute/unmute default input).
// On mute, warns if Siri / Apple Intelligence may still be listening.
// Persists pre-mute volume to ~/Library/Application Support/nospy/state.json
// so `off` restores what you had instead of jumping to a hardcoded value.
//
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

// MARK: - State (pre-mute volume persistence)

enum StateStore {
    static var dirURL: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("nospy", isDirectory: true)
    }
    static var fileURL: URL { dirURL.appendingPathComponent("state.json") }

    /// Saved pre-mute volume, or nil if missing/corrupt/out-of-range.
    static func loadPreMuteVolume() -> Int? {
        guard let data = try? Data(contentsOf: fileURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let v = obj["preMuteVolume"] as? Int,
              (0...100).contains(v)
        else { return nil }
        return v
    }

    /// Best-effort write; failures are swallowed so we never refuse to mute.
    static func savePreMuteVolume(_ v: Int) {
        do {
            try FileManager.default.createDirectory(
                at: dirURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            let obj: [String: Any] = ["preMuteVolume": v]
            let data = try JSONSerialization.data(withJSONObject: obj,
                                                  options: [.prettyPrinted])
            try data.write(to: fileURL, options: [.atomic])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                   ofItemAtPath: fileURL.path)
        } catch {
            // intentional: state persistence is non-critical
        }
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

// MARK: - Listening (is the mic actually in use?)
// "Is something listening RIGHT NOW?" — the question the orange dot in Control
// Center answers. We read kAudioDevicePropertyDeviceIsRunningSomewhere on the
// default input. Process attribution (which app holds the mic) uses the
// kAudioHardwarePropertyProcessObjectList family added in macOS 14; on older
// systems we report active/idle without names. No private APIs.

struct MicActivity {
    let active: Bool
    /// Bundle IDs (preferred) or "PID 1234" labels of processes using the mic.
    let consumers: [String]
    /// True if process-list enumeration ran (macOS 14+); false on older OSes.
    let attributionAvailable: Bool
}

private func defaultInputIsActive() -> Bool? {
    guard let device = defaultInputDeviceID() else { return nil }
    var running: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    let s = AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &running)
    return s == noErr ? (running != 0) : nil
}

@available(macOS 14.0, *)
private func micConsumerLabels() -> [String] {
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyProcessObjectList,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var dataSize: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),
                                         &addr, 0, nil, &dataSize) == noErr,
          dataSize > 0 else { return [] }
    let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
    var processObjects = [AudioObjectID](repeating: 0, count: count)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                     &addr, 0, nil, &dataSize, &processObjects) == noErr
    else { return [] }

    var labels: [String] = []
    for obj in processObjects {
        var inputRunning: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var inAddr = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningInput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(obj, &inAddr, 0, nil, &size, &inputRunning) == noErr,
              inputRunning != 0 else { continue }

        // Prefer bundle ID; fall back to PID.
        var bundleRef: Unmanaged<CFString>?
        var bSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var bAddr = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        if AudioObjectGetPropertyData(obj, &bAddr, 0, nil, &bSize, &bundleRef) == noErr,
           let unmanaged = bundleRef {
            let s = unmanaged.takeRetainedValue() as String
            if !s.isEmpty { labels.append(s); continue }
        }

        var pid: pid_t = 0
        var pSize = UInt32(MemoryLayout<pid_t>.size)
        var pAddr = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        if AudioObjectGetPropertyData(obj, &pAddr, 0, nil, &pSize, &pid) == noErr {
            labels.append("PID \(pid)")
        }
    }
    return labels
}

func micActivity() -> MicActivity {
    let active = defaultInputIsActive() ?? false
    if #available(macOS 14.0, *) {
        return MicActivity(active: active,
                           consumers: micConsumerLabels(),
                           attributionAvailable: true)
    }
    return MicActivity(active: active, consumers: [], attributionAvailable: false)
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

// MARK: - Siri / Apple Intelligence detection
// "Is something listening?" isn't a single bit on modern macOS. Siri, "Hey Siri"
// wake word, Dictation, and Apple Intelligence each have their own master
// switches across several preference domains, and the exact set of keys/domains
// changes between macOS versions. We probe a defensive superset: any signal we
// recognize as ON counts; missing keys/domains are treated as OFF (not errors).
//
// We use CFPreferencesCopyAppValue (in-process) instead of shelling out to
// `defaults` so a status check is one fast call, not 10+ subprocesses.

private func readDefaultsBool(_ domain: String, _ key: String) -> Bool {
    guard let v = CFPreferencesCopyAppValue(key as CFString, domain as CFString) else {
        return false
    }
    if CFGetTypeID(v) == CFBooleanGetTypeID() {
        return CFBooleanGetValue((v as! CFBoolean))
    }
    if let n = v as? NSNumber { return n.intValue != 0 }
    if let s = v as? String { return s == "1" || s.lowercased() == "true" }
    return false
}

struct SiriSignal {
    let label: String
    /// One or more (domain, key) probes; the signal is ON if any probe is ON.
    let sources: [(domain: String, key: String)]
    let on: Bool
}

struct SiriStatus {
    let signals: [SiriSignal]
    var anyOn: Bool { signals.contains { $0.on } }

    /// Inline one-line summary, e.g. "Siri assistant, Dictation ON".
    var compactSummary: String {
        let onLabels = signals.filter { $0.on }.map { $0.label }
        if onLabels.isEmpty { return "no Siri / Apple Intelligence signals on" }
        return onLabels.joined(separator: ", ") + " ON"
    }

    /// Per-signal breakdown lines, for `status` output.
    var detailedLines: [String] {
        signals.map { sig in
            "   \(sig.on ? "🟠 ON " : "⚪ off") \(sig.label)"
        }
    }
}

func readSiriStatus() -> SiriStatus {
    let defs: [(String, [(String, String)])] = [
        ("Siri assistant", [
            ("com.apple.assistant.support",  "Assistant Enabled"),
            ("com.apple.assistant.backedup", "Use Assistant"),
        ]),
        ("\"Hey Siri\" wake word", [
            ("com.apple.Siri",               "VoiceTriggerUserEnabled"),
            ("com.apple.assistant.support",  "Voice Trigger Enabled"),
        ]),
        ("Siri in menu bar", [
            ("com.apple.Siri",               "StatusMenuVisible"),
        ]),
        ("Dictation", [
            ("com.apple.assistant.support",  "Dictation Enabled"),
            ("com.apple.speech.recognition.AppleSpeechRecognition.prefs",
                                             "DictationIMMasterDictationEnabled"),
            ("com.apple.HIToolbox",          "AppleDictationAutoEnable"),
        ]),
        ("Apple Intelligence", [
            ("com.apple.intelligenceflags",     "Apple Intelligence Enabled"),
            ("com.apple.intelligenceflags",     "Enabled"),
            ("com.apple.intelligence",          "Enabled"),
            ("com.apple.intelligenceplatform",  "Enabled"),
        ]),
    ]
    let signals = defs.map { (label, sources) -> SiriSignal in
        let tuples = sources.map { (domain: $0.0, key: $0.1) }
        let on = tuples.contains { readDefaultsBool($0.domain, $0.key) }
        return SiriSignal(label: label, sources: tuples, on: on)
    }
    return SiriStatus(signals: signals)
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
    print("Usage: nospy [toggle|on|off|status|siri|listening]")
    print("  (no arg)  = toggle mute/unmute")
    print("  on        = force mute (saves current level first)")
    print("  off       = force unmute (restores saved level, or 80)")
    print("  status    = show mute + Siri breakdown + mic activity")
    print("  siri      = open System Settings → Siri pane")
    print("  listening = show which apps (if any) are currently using the mic")
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

if arg == "listening" {
    let m = micActivity()
    if m.active {
        var line = "🔴 Mic ACTIVE"
        if !m.consumers.isEmpty {
            line += " — " + m.consumers.joined(separator: ", ")
        } else if m.attributionAvailable {
            line += " (no process attribution available)"
        }
        print(line)
    } else {
        print("🟢 Mic idle")
    }
    if !m.attributionAvailable {
        print("   (process attribution requires macOS 14+; only active/idle reported)")
    }
    exit(0)
}

guard let current = getInputVolume() else {
    print("Failed to read current input volume")
    exit(1)
}

let isMuted = current == 0

if arg == "status" {
    let emoji = isMuted ? "🔴 Muted" : "🟢 Live"
    var line = "\(emoji) (input volume: \(current))"
    if isMuted, let saved = StateStore.loadPreMuteVolume() {
        line += " — pre-mute saved: \(saved)"
    }
    print(line)

    let m = micActivity()
    var micLine = "Mic: " + (m.active ? "🔴 ACTIVE" : "🟢 idle")
    if m.active && !m.consumers.isEmpty {
        micLine += " — " + m.consumers.joined(separator: ", ")
    }
    print(micLine)

    let siri = readSiriStatus()
    print("Siri / Apple Intelligence:")
    for l in siri.detailedLines { print(l) }
    if isMuted && siri.anyOn {
        print("⚠️ Input is muted, but the signals above can still process audio.")
        print("   Run 'nospy siri' to open the Siri settings pane.")
    }
    exit(0)
}

enum Action { case mute, unmute }
let action: Action
switch arg {
case "on", "mute":      action = .mute
case "off", "unmute":   action = .unmute
default:                action = isMuted ? .unmute : .mute    // toggle
}

let target: Int
switch action {
case .mute:
    if isMuted {
        print("🔴 Already muted (input volume: 0)")
        exit(0)
    }
    StateStore.savePreMuteVolume(current)
    target = 0
case .unmute:
    if !isMuted {
        print("🟢 Already unmuted (input volume: \(current))")
        exit(0)
    }
    target = StateStore.loadPreMuteVolume() ?? 80
}

if setInputVolume(target) {
    let emoji = target == 0 ? "🔴 Muted" : "🟢 Unmuted"
    print("\(emoji) (set to \(target))")
    if target == 0 {
        let siri = readSiriStatus()
        if siri.anyOn {
            print("⚠️ Mic input is 0, but these listening signals are still ON: \(siri.compactSummary)")
            print("   Auto-opening System Settings → Siri pane for easy disable...")
            if !openSiriSettings() {
                print("   Failed to auto-open. Run 'nospy siri' or go manually: System Settings > Apple Intelligence & Siri.")
            }
        }
    }
} else {
    print("Failed to set input volume")
    exit(1)
}

// nospy — CLI dispatcher. All logic lives in NoSpyCore; this file is only
// argparse + output formatting. The same NoSpyCore powers NoSpyBar.

import Foundation
import NoSpyCore

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

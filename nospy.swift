// nospy.swift
// CLI tool to toggle macOS microphone input volume (mute/unmute default input)
// Checks for Siri/Assistant activity on mute → auto-opens settings pane if enabled
// Compile: swiftc nospy.swift -o nospy

import Foundation

// MARK: - Helpers

func runAppleScript(_ script: String) -> Bool {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    task.arguments = ["-e", script]
    
    do {
        try task.run()
        task.waitUntilExit()
        return task.terminationStatus == 0
    } catch {
        print("Error running osascript: \(error)")
        return false
    }
}

func getInputVolume() -> Int? {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    task.arguments = ["-e", "input volume of (get volume settings)"]
    
    let pipe = Pipe()
    task.standardOutput = pipe
    
    do {
        try task.run()
        task.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           let vol = Int(str) {
            return vol
        }
    } catch {
        print("Error getting volume: \(error)")
    }
    return nil
}

func setInputVolume(_ target: Int) -> Bool {
    runAppleScript("set volume input volume \(target)")
}

func isAssistantEnabled() -> Bool {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
    task.arguments = ["read", "com.apple.assistant.support", "Assistant Enabled"]
    
    let pipe = Pipe()
    task.standardOutput = pipe
    
    do {
        try task.run()
        task.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
            // "1" or "true" means enabled
            return str == "1" || str.lowercased() == "true"
        }
    } catch {
        // If key missing or error, assume not enabled
    }
    return false
}

func openSiriSettings() -> Bool {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    task.arguments = ["x-apple.systempreferences:com.apple.Siri-Settings.extension"]
    
    do {
        try task.run()
        task.waitUntilExit()
        return task.terminationStatus == 0
    } catch {
        print("Error opening Siri settings: \(error)")
        return false
    }
}

// MARK: - Main logic

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

let success = setInputVolume(target)

if success {
    let emoji = target == 0 ? "🔴 Muted" : "🟢 Unmuted"
    print("\(emoji) (set to \(target))")
    
    // After muting, check Siri → auto-open if enabled
    if target == 0 && isAssistantEnabled() {
        print("⚠️ Heads up: 'Hey Siri' / 'Listen for Siri' may still detect sound even when muted.")
        print("   Auto-opening System Settings → Siri pane for easy disable...")
        if !openSiriSettings() {
            print("   Failed to auto-open. Run 'nospy siri' or go manually: System Settings > Apple Intelligence & Siri.")
        }
    }
} else {
    print("Failed to set input volume")
}

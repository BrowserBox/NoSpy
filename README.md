# NoSpy

A lightweight macOS microphone privacy toolkit. Two products in one repo:

- **`nospy`** — command-line mic mute/unmute with Siri + Apple Intelligence + mic-activity reporting.
- **`NoSpyBar`** — a tiny menu bar companion that does everything the CLI does from a click.

## The Problem

macOS lets you mute your microphone input, but "Listen for Siri" and Apple Intelligence can still process audio even when the system input volume is at zero, and there's no quick way to see *which apps* are using the mic right now. NoSpy gives you:

- One command (or one click) to mute and unmute, restoring your prior level rather than jumping to a hardcoded value.
- A per-signal breakdown of Siri / Apple Intelligence listening surfaces, not just one bit.
- A live "is anything using the mic right now?" answer with process attribution where macOS permits it.

## Install

```bash
git clone https://github.com/BrowserBox/NoSpy.git
cd NoSpy
swift build -c release

# Symlink (or copy) the CLI onto your PATH:
sudo ln -sf "$PWD/.build/release/nospy" /usr/local/bin/nospy

# Run the menu bar app (launches in the background; quit via its menu):
.build/release/NoSpyBar &
```

### Single-file `swiftc` fallback (CLI only)

If you'd rather not use SwiftPM, the CLI is still buildable from a single source file by concatenating NoSpyCore on top of the CLI dispatcher:

```bash
cat Sources/NoSpyCore/*.swift Sources/nospy/main.swift > nospy-singlefile.swift
swiftc nospy-singlefile.swift -o nospy
```

NoSpyBar requires SwiftPM (it links AppKit and depends on the shared library).

## CLI usage

```bash
nospy               # Toggle mute/unmute (restores your prior level on unmute)
nospy on            # Force mute (saves current level first)
nospy off           # Force unmute (restores saved level, or 80 if none saved)
nospy status        # Mute state + Siri/AI breakdown + mic activity
nospy siri          # Open System Settings → Siri pane
nospy listening     # Is the mic active right now? Which apps hold it?
nospy --help        # Show help
```

Example `nospy status` output:

```
🟢 Live (input volume: 50)
Mic: 🔴 ACTIVE — us.zoom.xos
Siri / Apple Intelligence:
   🟠 ON  "Hey Siri" wake word
   ⚪ off Siri assistant
   ⚪ off Siri in menu bar
   ⚪ off Dictation
   ⚪ off Apple Intelligence
```

## Menu bar app (NoSpyBar)

Click the mic icon in the menu bar for everything the CLI offers:

```
  🟢 Live (volume 50)               (header — current state)
  Siri / AI: all signals off        (header — Siri summary)
  🎤 Mic: idle                      (header — mic activity)
  ──────────────────────
  Toggle Mute             ⌘M
  Mute                              (disabled if already muted)
  Unmute                            (disabled if already live)
  ──────────────────────
  Open Siri Settings…
  Refresh Status
  ──────────────────────
  About NoSpy
  Quit NoSpyBar           ⌘Q
```

State auto-refreshes every 2 seconds and on menu-open. The mic icon changes between `mic.fill` (live) and `mic.slash.fill` (muted); a `⚠︎` glyph appears next to it when the mic is muted but a Siri / Apple Intelligence signal is still listening.

*(Screenshot placeholder — add `docs/nospybar.png` once captured.)*

## Threat model — what NoSpy actually does

NoSpy is a **software input-gain mute** with a privacy reminder. It is *not* a hardware kill switch. Specifically:

- **Mute is `kAudioDevicePropertyVolumeScalar = 0` on the default input device** (with an AppleScript fallback). This drops the captured audio level to zero across the system. Apps can still *open* the mic; they just receive silence. On hardware without software input gain (some USB DACs, certain BT headsets) the mute may not apply — verify with `nospy status` after a mute.
- **NoSpy does not revoke TCC microphone permissions.** Apps you've already granted mic access keep that permission. To actually deny an app, use System Settings → Privacy & Security → Microphone.
- **NoSpy does not silence "Hey Siri" or Apple Intelligence on its own.** It detects these listening signals (across `com.apple.assistant.support`, `com.apple.Siri`, `com.apple.intelligenceflags`, and friends) and warns you, but the actual disable has to happen in System Settings → Apple Intelligence & Siri. The CLI auto-opens that pane after a mute when any signal is on; the menu bar app shows the warning header.
- **The orange dot in Control Center remains the ground truth.** `nospy listening` reads the same HAL property (`kAudioDevicePropertyDeviceIsRunningSomewhere`) Apple's UI uses, but if your version of macOS shows the dot and NoSpy disagrees, trust the dot.
- **Process attribution requires macOS 14+.** Names of apps using the mic come from `kAudioHardwarePropertyProcessObjectList` — a public HAL API added in macOS 14. On older systems NoSpy reports active/idle without process names. NoSpy does **not** use private APIs.

## Why?

- **One command or one click** to mute your mic before sensitive conversations.
- **Visible warnings** when Siri / Apple Intelligence can still hear you despite system mute.
- **Zero dependencies** — pure Swift on top of Foundation, CoreAudio, CoreFoundation, AppKit.
- **Auditable** — total Swift code is small, split into focused files in `Sources/NoSpyCore/`.

## Requirements

- macOS 12+ (the CLI's mic-active check works on 12+; process attribution requires 14+).
- Swift toolchain (included with Xcode Command Line Tools).

## License

(c) BrowserBox / DOSAYGO. See license.txt.

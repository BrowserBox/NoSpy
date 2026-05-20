# NoSpy

Fork of [BrowserBox/NoSpy](https://github.com/BrowserBox/NoSpy). Adds a CoreAudio HAL fallback (works on USB/Bluetooth mics where v1 silently failed), per-signal Siri / Apple Intelligence detection, a `listening` subcommand, and a menu bar companion.

Two products: **`nospy`** (CLI) and **`NoSpyBar`** (menu bar app). Both share `NoSpyCore`.

## Install

```bash
git clone https://github.com/Sat-Stone/NoSpy.git
cd NoSpy
swift build -c release
sudo ln -sf "$PWD/.build/release/nospy" /usr/local/bin/nospy
.build/release/NoSpyBar &
```

Single-file CLI build (no SwiftPM):

```bash
cat Sources/NoSpyCore/*.swift Sources/nospy/main.swift > nospy-singlefile.swift
swiftc nospy-singlefile.swift -o nospy
```

NoSpyBar requires SwiftPM (links AppKit).

## CLI

```bash
nospy               # Toggle mute/unmute
nospy on            # Mute (saves current level)
nospy off           # Unmute (restores saved level, or 80)
nospy status        # Mute + Siri breakdown + mic activity
nospy listening     # Mic active? Which apps?
nospy siri          # Open Siri settings
nospy --help        # Help
```

Example `nospy status`:

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

## NoSpyBar

Click the mic icon for every CLI action. Auto-refreshes every 2s and on menu open. Icon: `mic.fill` (live) / `mic.slash.fill` (muted), with `⚠︎` when muted but Siri can still listen.

*(Screenshot: add `docs/nospybar.png`.)*

## Threat model

NoSpy is a **software input-gain mute**, not a hardware kill switch.

- Mute = `kAudioDevicePropertyVolumeScalar = 0` on the default input. Apps can still open the mic; they receive silence.
- Does **not** revoke TCC mic permissions — use System Settings → Privacy & Security → Microphone for that.
- Does **not** disable "Hey Siri" or Apple Intelligence directly; it detects and warns. Disable in System Settings.
- The orange dot in Control Center is ground truth. If it disagrees with `nospy listening`, trust the dot.
- Process attribution requires macOS 14+ (`kAudioHardwarePropertyProcessObjectList`, public API). No private APIs anywhere.

## Requirements

macOS 12+ (process attribution: 14+). Swift toolchain (Xcode Command Line Tools).

## License

(c) BrowserBox / DOSAYGO. See `license.txt`.

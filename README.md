# NoSpy

A lightweight macOS command-line tool for microphone privacy control.

## The Problem

macOS lets you mute your microphone input, but "Listen for Siri" (and Apple Intelligence) can still detect audio even when the system input volume is set to zero. NoSpy gives you quick toggle control and warns you when background listening is still active.

## Install

```bash
# Clone and compile
git clone https://github.com/BrowserBox/NoSpy.git
cd NoSpy
swiftc nospy.swift -o nospy

# Optionally move to PATH
sudo mv nospy /usr/local/bin/
```

## Usage

```bash
nospy              # Toggle mute/unmute
nospy on           # Mute microphone
nospy off          # Unmute microphone
nospy status       # Show current state + Siri warning if enabled
nospy siri         # Open Siri settings to disable background listening
nospy --help       # Show help
```

## Example

```
$ nospy status
🔴 Microphone is MUTED (input volume: 0)
⚠️  Siri/Apple Intelligence is ENABLED — "Listen for Siri" can still hear you.
   Run `nospy siri` to open settings and disable it.
```

## Why?

- **One command** to mute your mic before sensitive conversations
- **Visible warnings** when Siri can still listen despite system mute
- **Zero dependencies** — pure Swift using built-in macOS APIs
- **156 lines** — easy to audit

## Requirements

- macOS 12+
- Swift (included with Xcode Command Line Tools)

## License

(c) BrowserBox / DOSAYGO. See license.txt.

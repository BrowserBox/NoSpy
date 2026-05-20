// StatusController — owns the NSStatusItem and its menu. Refreshes state every
// 2s (low CPU; no audio buffers, just HAL property reads + CFPreferences) and
// also on menu-open via NSMenuDelegate. Every menu action calls into NoSpyCore
// the same way the CLI does, then triggers a refresh so the UI updates
// immediately instead of waiting for the next tick.

import AppKit
import NoSpyCore

final class StatusController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var timer: Timer?

    // Header items reflect current state; they're disabled (informational only).
    private let muteHeader  = NSMenuItem(title: "—", action: nil, keyEquivalent: "")
    private let siriHeader  = NSMenuItem(title: "—", action: nil, keyEquivalent: "")
    private let micHeader   = NSMenuItem(title: "—", action: nil, keyEquivalent: "")

    // Action items — enabled/disabled depending on current state.
    private let toggleItem = NSMenuItem(title: "Toggle Mute",
                                        action: #selector(toggleMute),
                                        keyEquivalent: "m")
    private let muteItem   = NSMenuItem(title: "Mute",
                                        action: #selector(mute),
                                        keyEquivalent: "")
    private let unmuteItem = NSMenuItem(title: "Unmute",
                                        action: #selector(unmute),
                                        keyEquivalent: "")

    // MARK: NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = buildMenu()
        statusItem.menu?.delegate = self
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        if let t = timer { RunLoop.main.add(t, forMode: .common) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
    }

    // MARK: Menu construction

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        muteHeader.isEnabled = false
        siriHeader.isEnabled = false
        micHeader.isEnabled  = false
        menu.addItem(muteHeader)
        menu.addItem(siriHeader)
        menu.addItem(micHeader)
        menu.addItem(.separator())

        toggleItem.target = self
        muteItem.target   = self
        unmuteItem.target = self
        menu.addItem(toggleItem)
        menu.addItem(muteItem)
        menu.addItem(unmuteItem)
        menu.addItem(.separator())

        let siriSettingsItem = NSMenuItem(title: "Open Siri Settings…",
                                          action: #selector(openSiri),
                                          keyEquivalent: "")
        siriSettingsItem.target = self
        menu.addItem(siriSettingsItem)

        let refreshItem = NSMenuItem(title: "Refresh Status",
                                     action: #selector(refresh),
                                     keyEquivalent: "")
        refreshItem.target = self
        menu.addItem(refreshItem)
        menu.addItem(.separator())

        let aboutItem = NSMenuItem(title: "About NoSpy",
                                   action: #selector(showAbout),
                                   keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "Quit NoSpyBar",
                                  action: #selector(quit),
                                  keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    // MARK: State refresh

    @objc func refresh() {
        let vol = getInputVolume() ?? 0
        let isMuted = vol == 0
        let siri = readSiriStatus()
        let mic = micActivity()

        let symbol = isMuted ? "mic.slash.fill" : "mic.fill"
        let desc = isMuted ? "Microphone muted" : "Microphone live"
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: desc) {
            img.isTemplate = true
            statusItem.button?.image = img
        }
        // Warning glyph next to the icon when muted but Siri can still listen.
        statusItem.button?.title = (isMuted && siri.anyOn) ? " ⚠︎" : ""

        if isMuted {
            let saved = StateStore.loadPreMuteVolume()
            muteHeader.title = saved != nil
                ? "🔴 Muted (was \(saved!))"
                : "🔴 Muted"
        } else {
            muteHeader.title = "🟢 Live (volume \(vol))"
        }

        siriHeader.title = siri.anyOn
            ? "⚠️ " + siri.compactSummary
            : "Siri / AI: all signals off"

        if mic.active {
            var s = "🔴 Mic ACTIVE"
            if !mic.consumers.isEmpty {
                s += " — " + mic.consumers.joined(separator: ", ")
            }
            micHeader.title = s
        } else {
            micHeader.title = "🎤 Mic: idle"
        }

        muteItem.isEnabled   = !isMuted
        unmuteItem.isEnabled = isMuted
    }

    // MARK: NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        refresh()
    }

    // MARK: Actions

    @objc private func toggleMute() {
        guard let cur = getInputVolume() else { return }
        if cur == 0 {
            let target = StateStore.loadPreMuteVolume() ?? 80
            _ = setInputVolume(target)
        } else {
            StateStore.savePreMuteVolume(cur)
            _ = setInputVolume(0)
        }
        refresh()
    }

    @objc private func mute() {
        guard let cur = getInputVolume(), cur != 0 else { return }
        StateStore.savePreMuteVolume(cur)
        _ = setInputVolume(0)
        refresh()
    }

    @objc private func unmute() {
        let target = StateStore.loadPreMuteVolume() ?? 80
        _ = setInputVolume(target)
        refresh()
    }

    @objc private func openSiri() {
        _ = openSiriSettings()
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "NoSpy"
        alert.informativeText = """
        Quick mic mute toggle with Siri privacy check.

        Mutes by setting the input volume to 0. "Hey Siri" and Apple \
        Intelligence may still listen even when the input is muted, so \
        the header tells you when those listening signals are on.

        NoSpy is a software input-gain mute — not a hardware kill switch \
        and not a TCC permission revoker. The orange dot in Control \
        Center remains the ground truth for whether your mic is active.
        """
        alert.alertStyle = .informational
        alert.runModal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

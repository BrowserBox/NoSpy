// Siri / Apple Intelligence detection. "Is something listening?" isn't one bit
// on modern macOS — Siri, "Hey Siri" wake word, Dictation, and Apple Intelligence
// each have their own master switches across several preference domains, and
// the exact set of keys/domains shifts between macOS versions. We probe a
// defensive superset and treat missing keys/domains as OFF, not errors.
//
// Uses CFPreferencesCopyAppValue (in-process, public CF API) instead of shelling
// out to `defaults` so a single status check is one fast call.

import Foundation
import CoreFoundation

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

public struct SiriSignal {
    public let label: String
    /// One or more (domain, key) probes; the signal is ON if any probe is ON.
    public let sources: [(domain: String, key: String)]
    public let on: Bool
}

public struct SiriStatus {
    public let signals: [SiriSignal]
    public var anyOn: Bool { signals.contains { $0.on } }

    /// Inline one-line summary, e.g. "Siri assistant, Dictation ON".
    public var compactSummary: String {
        let onLabels = signals.filter { $0.on }.map { $0.label }
        if onLabels.isEmpty { return "no Siri / Apple Intelligence signals on" }
        return onLabels.joined(separator: ", ") + " ON"
    }

    /// Per-signal breakdown lines, for `status` output.
    public var detailedLines: [String] {
        signals.map { sig in
            "   \(sig.on ? "🟠 ON " : "⚪ off") \(sig.label)"
        }
    }
}

public func readSiriStatus() -> SiriStatus {
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

public func openSiriSettings() -> Bool {
    runProcess("/usr/bin/open",
               ["x-apple.systempreferences:com.apple.Siri-Settings.extension"]).ok
}

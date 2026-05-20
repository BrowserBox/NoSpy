// State persistence — saves the pre-mute volume so `off` restores what you had,
// not a hardcoded value. Lives at ~/Library/Application Support/nospy/state.json
// with directory mode 0700 and file mode 0600. Failures are best-effort: state
// is non-critical, and we never refuse to mute because the disk got weird.

import Foundation

public enum StateStore {
    public static var dirURL: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("nospy", isDirectory: true)
    }
    public static var fileURL: URL { dirURL.appendingPathComponent("state.json") }

    /// Saved pre-mute volume, or nil if missing/corrupt/out-of-range.
    public static func loadPreMuteVolume() -> Int? {
        guard let data = try? Data(contentsOf: fileURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let v = obj["preMuteVolume"] as? Int,
              (0...100).contains(v)
        else { return nil }
        return v
    }

    /// Best-effort write; failures are swallowed so we never refuse to mute.
    public static func savePreMuteVolume(_ v: Int) {
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

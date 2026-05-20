// Process helpers — shell-out plumbing used by every subsystem that needs to
// invoke a system binary (osascript, open). Captures stdout/stderr/status in
// one struct so callers can decide what to surface to the user.

import Foundation

public struct ProcResult {
    public let status: Int32
    public let stdout: String
    public let stderr: String
    public var ok: Bool { status == 0 }
}

public func runProcess(_ executable: String, _ args: [String]) -> ProcResult {
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

public func runAppleScript(_ script: String) -> ProcResult {
    runProcess("/usr/bin/osascript", ["-e", script])
}

public func explainOsascriptFailure(_ r: ProcResult) {
    let s = r.stderr.lowercased()
    if s.contains("not authorized") || s.contains("not allowed") || s.contains("-1743") {
        print("⚠️ osascript was denied. Grant your terminal Automation access:")
        print("   System Settings → Privacy & Security → Automation → (your terminal) → System Events.")
    } else if !r.stderr.isEmpty {
        print("osascript: \(r.stderr)")
    }
}

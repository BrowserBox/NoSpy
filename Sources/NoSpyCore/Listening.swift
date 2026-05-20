// "Is the mic in use right now?" — the question the orange dot in Control
// Center answers. kAudioDevicePropertyDeviceIsRunningSomewhere gives the
// active/idle bit on macOS 12+. Process attribution (which app is using the
// mic) uses kAudioHardwarePropertyProcessObjectList & friends, all public
// HAL APIs available on macOS 14+. No private APIs.

import Foundation
import CoreAudio

public struct MicActivity {
    public let active: Bool
    /// Bundle IDs (preferred) or "PID 1234" labels of processes using the mic.
    public let consumers: [String]
    /// True if process-list enumeration ran (macOS 14+); false on older OSes.
    public let attributionAvailable: Bool
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

public func micActivity() -> MicActivity {
    let active = defaultInputIsActive() ?? false
    if #available(macOS 14.0, *) {
        return MicActivity(active: active,
                           consumers: micConsumerLabels(),
                           attributionAvailable: true)
    }
    return MicActivity(active: active, consumers: [], attributionAvailable: false)
}

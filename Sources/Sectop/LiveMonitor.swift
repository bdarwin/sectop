import AppKit
import CoreAudio
import CoreMediaIO

struct LiveApp: Hashable, Identifiable {
    let pid: pid_t
    let bundleID: String
    var id: pid_t { pid }

    @MainActor var name: String {
        if let app = NSRunningApplication(processIdentifier: pid), let n = app.localizedName { return n }
        return bundleID.isEmpty ? "pid \(pid)" : AppResolver.shared.info(bundleID: bundleID).name
    }
}

/// Watches whether the microphone or camera is in use right now, and by whom.
@MainActor
final class LiveMonitor: ObservableObject {
    @Published private(set) var micInUse = false
    @Published private(set) var cameraInUse = false
    @Published private(set) var micApps: [LiveApp] = []
    var anyInUse: Bool { micInUse || cameraInUse }

    private var timer: Timer?

    init() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    func poll() {
        let apps = AudioProbe.processesUsingInput()
        let mic = apps.map { !$0.isEmpty } ?? AudioProbe.anyInputDeviceRunning()
        let cam = CameraProbe.anyCameraRunning()
        if mic != micInUse { micInUse = mic }
        if cam != cameraInUse { cameraInUse = cam }
        let list = apps ?? []
        if list != micApps { micApps = list }
    }
}

enum AudioProbe {
    private static let system = AudioObjectID(kAudioObjectSystemObject)

    private static func address(_ sel: AudioObjectPropertySelector,
                                _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func ids(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector,
                            _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [AudioObjectID] {
        var addr = address(sel, scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(obj, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var out = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, &out) == noErr else { return [] }
        return out
    }

    private static func scalar<T>(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector, _ initial: T) -> T? {
        var addr = address(sel)
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func string(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector) -> String? {
        var addr = address(sel)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    /// Per-process input use (macOS 14.2+). Returns nil when unsupported.
    static func processesUsingInput() -> [LiveApp]? {
        guard #available(macOS 14.2, *) else { return nil }
        var result: [LiveApp] = []
        for proc in ids(system, kAudioHardwarePropertyProcessObjectList) {
            guard scalar(proc, kAudioProcessPropertyIsRunningInput, UInt32(0)) == 1 else { continue }
            let pid = scalar(proc, kAudioProcessPropertyPID, pid_t(0)) ?? 0
            result.append(LiveApp(pid: pid, bundleID: string(proc, kAudioProcessPropertyBundleID) ?? ""))
        }
        return result.sorted { $0.pid < $1.pid }
    }

    static func anyInputDeviceRunning() -> Bool {
        ids(system, kAudioHardwarePropertyDevices).contains { dev in
            !ids(dev, kAudioDevicePropertyStreams, kAudioObjectPropertyScopeInput).isEmpty
                && scalar(dev, kAudioDevicePropertyDeviceIsRunningSomewhere, UInt32(0)) == 1
        }
    }
}

enum CameraProbe {
    static func anyCameraRunning() -> Bool {
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var addr = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return false }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &addr, 0, nil, size, &used, &devices) == noErr else { return false }

        addr.mSelector = CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere)
        return devices.contains { dev in
            var running: UInt32 = 0
            return CMIOObjectGetPropertyData(dev, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &running) == noErr
                && running != 0
        }
    }
}

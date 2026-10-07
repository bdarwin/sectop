import AppKit
import ServiceManagement

/// Runs `work` off the main thread and delivers its result on the main actor.
func background<T>(_ work: @escaping () -> T, then done: @escaping @MainActor (T) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
        let value = work()
        DispatchQueue.main.async { MainActor.assumeIsolated { done(value) } }
    }
}

@MainActor
final class PrivacyStore: ObservableObject {
    @Published private(set) var entries: [TCCEntry] = []
    @Published private(set) var hasFullDiskAccess = true
    @Published private(set) var loading = false
    @Published private(set) var busy: Set<String> = []
    @Published var message: String?

    func refresh() {
        loading = true
        background({ () -> (Bool, [TCCEntry]) in
            do {
                var rows = try TCC.read(.user)
                rows += (try? TCC.read(.system)) ?? []
                return (true, rows)
            } catch {
                return (false, [])
            }
        }) { [weak self] ok, rows in
            self?.hasFullDiskAccess = ok
            self?.entries = rows
            self?.loading = false
        }
    }

    func set(_ entry: TCCEntry, allowed: Bool) {
        // macOS only lets apps reset permissions, never grant them.
        guard !allowed, entry.clientType == 0 else {
            SystemSettings.privacy(entry.info.anchor)
            return
        }
        busy.insert(entry.id)
        background({ TCC.revoke(entry) }) { [weak self] error in
            self?.busy.remove(entry.id)
            self?.message = error
            self?.refresh()
        }
    }
}

@MainActor
final class StartupStore: ObservableObject {
    @Published private(set) var items: [LaunchItem] = []
    @Published private(set) var busy: Set<String> = []
    @Published var message: String?

    func refresh() {
        background(LaunchItems.scan) { [weak self] in self?.items = $0 }
    }

    func set(_ item: LaunchItem, enabled: Bool) {
        busy.insert(item.id)
        background({ LaunchItems.set(item, enabled: enabled) }) { [weak self] error in
            self?.busy.remove(item.id)
            self?.message = error
            self?.refresh()
        }
    }
}

@MainActor
final class SharingStore: ObservableObject {
    @Published private(set) var state: [String: Bool] = [:]
    @Published private(set) var busy: Set<String> = []
    @Published var message: String?

    func refresh() {
        background({ Dictionary(uniqueKeysWithValues: SharingService.all.map { ($0.label, SharingService.isOn($0)) }) }) {
            [weak self] in self?.state = $0
        }
    }

    func set(_ service: SharingService, on: Bool) {
        busy.insert(service.id)
        background({ SharingService.set(service, on: on) }) { [weak self] error in
            self?.busy.remove(service.id)
            self?.message = error
            self?.refresh()
        }
    }
}

@MainActor
final class NetworkStore: ObservableObject {
    @Published private(set) var processes: [NetProcess] = []
    @Published private(set) var loading = false

    func refresh() {
        loading = true
        background(Network.scan) { [weak self] in
            self?.processes = $0
            self?.loading = false
        }
    }

    func quit(_ p: NetProcess) {
        if let app = NSRunningApplication(processIdentifier: p.pid) {
            app.terminate()
        } else {
            kill(p.pid, SIGTERM)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.refresh() }
    }
}

enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Sectop: launch at login failed: \(error)")
        }
    }
}

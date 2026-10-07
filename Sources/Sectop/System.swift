import AppKit

// MARK: - Launch agents & daemons

enum LaunchDomain: String, CaseIterable {
    case userAgent = "Your Login Agents"
    case globalAgent = "Login Agents (all users)"
    case daemon = "System Daemons"

    var directory: String {
        switch self {
        case .userAgent: NSHomeDirectory() + "/Library/LaunchAgents"
        case .globalAgent: "/Library/LaunchAgents"
        case .daemon: "/Library/LaunchDaemons"
        }
    }
    var needsAdmin: Bool { self == .daemon }
}

struct LaunchItem: Identifiable, Hashable {
    let label: String
    let plistPath: String
    let program: String?
    let domain: LaunchDomain
    let enabled: Bool
    let loaded: Bool
    var id: String { plistPath }
}

enum LaunchItems {
    static var uid: String { String(getuid()) }

    static func scan() -> [LaunchItem] {
        let guiOverrides = overrides("gui/\(uid)")
        let systemOverrides = overrides("system")
        let guiLoaded = Set(Shell.run("/bin/launchctl", ["list"]).out
            .split(separator: "\n").dropFirst()
            .compactMap { $0.split(separator: "\t").last.map(String.init) })

        var items: [LaunchItem] = []
        for domain in LaunchDomain.allCases {
            let files = (try? FileManager.default.contentsOfDirectory(atPath: domain.directory)) ?? []
            for file in files where file.hasSuffix(".plist") {
                let path = domain.directory + "/" + file
                guard let data = FileManager.default.contents(atPath: path),
                      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                      let label = plist["Label"] as? String else { continue }
                let program = plist["Program"] as? String ?? (plist["ProgramArguments"] as? [String])?.first
                let override = (domain == .daemon ? systemOverrides : guiOverrides)[label]
                let disabled = override ?? (plist["Disabled"] as? Bool ?? false)
                let loaded = domain == .daemon
                    ? Shell.run("/bin/launchctl", ["print", "system/\(label)"]).ok
                    : guiLoaded.contains(label)
                items.append(LaunchItem(label: label, plistPath: path, program: program, domain: domain,
                                        enabled: !disabled, loaded: loaded))
            }
        }
        return items.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    /// Parses `launchctl print-disabled`, returning label → isDisabled.
    private static func overrides(_ target: String) -> [String: Bool] {
        var map: [String: Bool] = [:]
        let regex = #/"([^"]+)" => (\w+)/#
        for line in Shell.run("/bin/launchctl", ["print-disabled", target]).out.split(separator: "\n") {
            if let m = line.firstMatch(of: regex) {
                map[String(m.1)] = m.2 == "disabled" || m.2 == "true"
            }
        }
        return map
    }

    /// Returns nil on success or cancel, else an error message.
    static func set(_ item: LaunchItem, enabled: Bool) -> String? {
        let target = item.domain == .daemon ? "system" : "gui/\(uid)"
        let service = "\(target)/\(item.label)"
        let commands = enabled
            ? ["/bin/launchctl enable \(Shell.quote(service))",
               "/bin/launchctl bootstrap \(target) \(Shell.quote(item.plistPath)) 2>/dev/null; true"]
            : ["/bin/launchctl bootout \(Shell.quote(service)) 2>/dev/null; true",
               "/bin/launchctl disable \(Shell.quote(service))"]
        let script = commands.joined(separator: " ; ")
        let r = item.domain.needsAdmin ? Shell.runAsAdmin(script) : Shell.run("/bin/sh", ["-c", script])
        if r.cancelled { return nil }
        return r.ok ? nil : r.err.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Sharing services

struct SharingService: Identifiable, Hashable {
    let name: String
    let detail: String
    let symbol: String
    let label: String
    let plist: String
    var id: String { label }

    static let all: [SharingService] = [
        SharingService(name: "Remote Login (SSH)", detail: "Others can log in to a shell on this Mac",
                       symbol: "terminal.fill", label: "com.openssh.sshd",
                       plist: "/System/Library/LaunchDaemons/ssh.plist"),
        SharingService(name: "Screen Sharing", detail: "Others can see and control your screen",
                       symbol: "display", label: "com.apple.screensharing",
                       plist: "/System/Library/LaunchDaemons/com.apple.screensharing.plist"),
        SharingService(name: "File Sharing (SMB)", detail: "Others can access shared folders",
                       symbol: "folder.badge.person.crop", label: "com.apple.smbd",
                       plist: "/System/Library/LaunchDaemons/com.apple.smbd.plist"),
        SharingService(name: "Remote Apple Events", detail: "Apps on other Macs can script this Mac",
                       symbol: "applescript.fill", label: "com.apple.AEServer",
                       plist: "/System/Library/LaunchDaemons/com.apple.eppc.plist"),
    ]

    static func isOn(_ s: SharingService) -> Bool {
        Shell.run("/bin/launchctl", ["print", "system/\(s.label)"]).ok
    }

    static func set(_ s: SharingService, on: Bool) -> String? {
        let svc = Shell.quote("system/\(s.label)")
        let script = on
            ? "/bin/launchctl enable \(svc) ; /bin/launchctl bootstrap system \(Shell.quote(s.plist)) 2>/dev/null; true"
            : "/bin/launchctl bootout \(svc) 2>/dev/null ; /bin/launchctl disable \(svc)"
        let r = Shell.runAsAdmin(script)
        if r.cancelled { return nil }
        return r.ok ? nil : r.err.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Network connections

struct NetProcess: Identifiable, Hashable {
    let pid: pid_t
    let command: String
    let path: String
    var remotes: [String]
    var listening: [String]
    var id: pid_t { pid }
}

enum Network {
    /// Snapshot of processes with open internet sockets. Without root, only your own processes are visible.
    static func scan() -> [NetProcess] {
        let out = Shell.run("/usr/sbin/lsof", ["-nP", "-i", "-F", "pcnT"]).out
        var procs: [pid_t: NetProcess] = [:]
        var pid: pid_t = 0
        var command = ""
        var name = ""

        func flush() {
            guard !name.isEmpty, pid > 0 else { return }
            if name.contains("->") {
                let remote = String(name.split(separator: ">").last ?? "")
                procs[pid]?.remotes.append(remote)
            }
            name = ""
        }

        for line in out.split(separator: "\n") {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p":
                flush()
                pid = pid_t(value) ?? 0
                command = ""
            case "c":
                command = value
                if procs[pid] == nil {
                    procs[pid] = NetProcess(pid: pid, command: command, path: executablePath(pid) ?? command,
                                            remotes: [], listening: [])
                }
            case "f":
                flush()
            case "n":
                name = value
            case "T":
                if value == "ST=LISTEN", !name.isEmpty {
                    procs[pid]?.listening.append(name)
                    name = ""
                }
            default: break
            }
        }
        flush()

        return procs.values
            .map { p in
                var p = p
                p.remotes = Array(Set(p.remotes)).sorted()
                p.listening = Array(Set(p.listening)).sorted()
                return p
            }
            .filter { !$0.remotes.isEmpty || !$0.listening.isEmpty }
            .sorted { $0.remotes.count + $0.listening.count > $1.remotes.count + $1.listening.count }
    }

    static func executablePath(_ pid: pid_t) -> String? {
        var buf = [CChar](repeating: 0, count: 4096)
        return proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 ? String(cString: buf) : nil
    }
}

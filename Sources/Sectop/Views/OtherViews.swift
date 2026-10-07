import SwiftUI

struct StartupView: View {
    @EnvironmentObject var store: StartupStore

    var body: some View {
        VStack(spacing: 0) {
            MessageBar(message: $store.message)
            List {
                ForEach(LaunchDomain.allCases, id: \.self) { domain in
                    let items = store.items.filter { $0.domain == domain }
                    if !items.isEmpty {
                        Section {
                            ForEach(items) { LaunchRow(item: $0) }
                        } header: {
                            HStack {
                                Text(domain.rawValue)
                                if domain.needsAdmin {
                                    Image(systemName: "lock.fill").help("Changing these asks for your admin password")
                                }
                            }
                        }
                    }
                }
                Section {
                    Button("Login Items & background apps in System Settings…") {
                        SystemSettings.open(SystemSettings.loginItems)
                    }
                    .buttonStyle(.link)
                } footer: {
                    Text("Apps that register login items with macOS directly are managed there.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .listStyle(.inset)
        }
    }
}

private struct LaunchRow: View {
    @EnvironmentObject var store: StartupStore
    let item: LaunchItem

    var body: some View {
        let app = item.program.map { AppResolver.shared.info(path: $0) }
        HStack(spacing: 8) {
            IconView(image: app?.icon ?? NSWorkspace.shared.icon(for: .unixExecutable), size: 20)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(item.label).lineLimit(1).truncationMode(.middle)
                    if item.loaded {
                        Circle().fill(.green).frame(width: 6, height: 6).help("Loaded")
                    }
                }
                Text(item.program ?? item.plistPath)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            BusySwitch(isOn: item.enabled, busy: store.busy.contains(item.id)) { store.set(item, enabled: $0) }
        }
        .contextMenu {
            Button("Show plist in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.plistPath)])
            }
            if let program = item.program {
                Button("Show program in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: program)])
                }
            }
        }
    }
}

struct SharingView: View {
    @EnvironmentObject var store: SharingStore

    var body: some View {
        VStack(spacing: 0) {
            MessageBar(message: $store.message)
            List {
                Section {
                    ForEach(SharingService.all) { service in
                        HStack(spacing: 10) {
                            Image(systemName: service.symbol).frame(width: 22).foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(service.name)
                                Text(service.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            BusySwitch(isOn: store.state[service.label] ?? false,
                                       busy: store.busy.contains(service.id)) { store.set(service, on: $0) }
                        }
                        .padding(.vertical, 2)
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Changing these asks for your admin password.")
                        Button("Sharing in System Settings…") { SystemSettings.open(SystemSettings.sharing) }
                            .buttonStyle(.link)
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
            .listStyle(.inset)
        }
    }
}

struct NetworkView: View {
    @EnvironmentObject var store: NetworkStore

    var body: some View {
        if store.processes.isEmpty {
            EmptyState(symbol: "network", text: store.loading ? "Scanning…" : "No open connections found.")
        } else {
            List {
                Section {
                    ForEach(store.processes) { NetRow(process: $0) }
                } footer: {
                    Text("Snapshot of your apps' open connections. System processes need admin rights to see.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .listStyle(.inset)
        }
    }
}

private struct NetRow: View {
    @EnvironmentObject var store: NetworkStore
    let process: NetProcess

    var body: some View {
        let app = AppResolver.shared.info(path: process.path)
        DisclosureGroup {
            ForEach(process.listening, id: \.self) {
                Label("Listening on \($0)", systemImage: "ear").font(.caption.monospaced())
            }
            ForEach(process.remotes, id: \.self) {
                Label($0, systemImage: "arrow.up.right").font(.caption.monospaced())
            }
        } label: {
            HStack(spacing: 8) {
                IconView(image: app.icon, size: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name == process.command ? app.name : "\(app.name) — \(process.command)").lineLimit(1)
                    Text(summary).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Quit") { store.quit(process) }
                    .controlSize(.small)
                    .help("Quit this process (pid \(process.pid))")
            }
        }
    }

    private var summary: String {
        var parts: [String] = []
        if !process.remotes.isEmpty { parts.append("\(process.remotes.count) connection\(process.remotes.count == 1 ? "" : "s")") }
        if !process.listening.isEmpty { parts.append("listening on \(process.listening.count) port\(process.listening.count == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }
}

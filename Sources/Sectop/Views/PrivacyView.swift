import SwiftUI

struct PrivacyView: View {
    @EnvironmentObject var store: PrivacyStore
    @AppStorage("privacy.byApp") private var byApp = true
    @AppStorage("privacy.showDenied") private var showDenied = false
    @AppStorage("privacy.showOther") private var showOther = false
    @State private var search = ""

    var body: some View {
        if !store.hasFullDiskAccess {
            FullDiskAccessPrompt()
        } else {
            VStack(spacing: 0) {
                controls
                MessageBar(message: $store.message)
                if visible.isEmpty {
                    EmptyState(symbol: "checkmark.shield", text: store.loading ? "Loading…" : "No permissions match.")
                } else {
                    List {
                        if byApp { appSections } else { serviceSections }
                    }
                    .listStyle(.inset)
                }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            TextField("Search apps or permissions", text: $search)
                .textFieldStyle(.roundedBorder)
            Picker("", selection: $byApp) {
                Image(systemName: "app.badge").tag(true).help("Group by app")
                Image(systemName: "list.bullet.rectangle").tag(false).help("Group by permission")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Menu {
                Toggle("Show denied", isOn: $showDenied)
                Toggle("Show other system permissions", isOn: $showOther)
                Divider()
                Button("Location Services…") { SystemSettings.open(SystemSettings.location) }
                Button("Privacy & Security…") { SystemSettings.privacy(nil) }
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var visible: [TCCEntry] {
        let q = search.lowercased()
        return store.entries.filter { e in
            (showDenied || e.isAllowed)
                && (showOther || e.info.isKnown)
                && (q.isEmpty || e.client.lowercased().contains(q) || e.info.name.lowercased().contains(q)
                    || AppResolver.shared.info(for: e).name.lowercased().contains(q))
        }
    }

    @ViewBuilder private var appSections: some View {
        let groups = Dictionary(grouping: visible, by: \.client)
            .map { (client: $0.key, entries: $0.value, info: AppResolver.shared.info(for: $0.value[0])) }
            .sorted { $0.info.name.localizedCaseInsensitiveCompare($1.info.name) == .orderedAscending }
        ForEach(groups, id: \.client) { group in
            DisclosureGroup {
                ForEach(sortByService(group.entries)) { entry in
                    EntryRow(entry: entry, title: entry.info.name, symbol: entry.info.symbol)
                }
            } label: {
                HStack(spacing: 8) {
                    IconView(image: group.info.icon)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(group.info.name).lineLimit(1)
                        HStack(spacing: 3) {
                            ForEach(Array(Set(group.entries.filter(\.isAllowed).map(\.service))).sorted(), id: \.self) {
                                Image(systemName: TCCService.named($0).symbol)
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(group.entries.filter(\.isAllowed).count)")
                        .font(.caption.monospacedDigit())
                        .padding(.horizontal, 6)
                        .background(.quaternary, in: Capsule())
                }
            }
        }
    }

    @ViewBuilder private var serviceSections: some View {
        let groups = Dictionary(grouping: visible, by: \.service)
        ForEach(sortedServices(Array(groups.keys)), id: \.self) { service in
            let info = TCCService.named(service)
            Section {
                ForEach(groups[service]!.sorted { AppResolver.shared.info(for: $0).name < AppResolver.shared.info(for: $1).name }) { entry in
                    EntryRow(entry: entry, title: AppResolver.shared.info(for: entry).name,
                             icon: AppResolver.shared.info(for: entry).icon)
                }
            } header: {
                HStack {
                    Label(info.name, systemImage: info.symbol)
                    Spacer()
                    Button("Settings") { SystemSettings.privacy(info.anchor) }
                        .buttonStyle(.borderless).font(.caption)
                }
            }
        }
    }

    private func sortedServices(_ keys: [String]) -> [String] {
        keys.sorted { a, b in
            let ia = TCCService.order.firstIndex(of: a) ?? Int.max
            let ib = TCCService.order.firstIndex(of: b) ?? Int.max
            return ia == ib ? a < b : ia < ib
        }
    }

    private func sortByService(_ entries: [TCCEntry]) -> [TCCEntry] {
        let order = sortedServices(Array(Set(entries.map(\.service))))
        return entries.sorted { (order.firstIndex(of: $0.service)!, $0.indirect) < (order.firstIndex(of: $1.service)!, $1.indirect) }
    }
}

private struct EntryRow: View {
    @EnvironmentObject var store: PrivacyStore
    let entry: TCCEntry
    let title: String
    var symbol: String? = nil
    var icon: NSImage? = nil

    var body: some View {
        HStack(spacing: 8) {
            if let icon { IconView(image: icon, size: 18) }
            if let symbol { Image(systemName: symbol).frame(width: 18).foregroundStyle(.secondary) }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            BusySwitch(isOn: entry.isAllowed, busy: store.busy.contains(entry.id)) { on in
                store.set(entry, allowed: on)
            }
            .help(help)
        }
        .contextMenu {
            Button("Open in System Settings") { SystemSettings.privacy(entry.info.anchor) }
            Button("Copy identifier") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.client, forType: .string)
            }
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if let target = entry.automationTarget {
            parts.append("→ " + AppResolver.shared.info(bundleID: target).name)
        }
        if entry.isLimited { parts.append("limited") }
        if !entry.isAllowed { parts.append("denied") }
        if entry.scope == .system { parts.append("system-wide") }
        return parts.joined(separator: " · ")
    }

    private var help: String {
        if !entry.isAllowed { return "Opens System Settings. macOS only lets you grant access there." }
        if entry.clientType != 0 { return "Opens System Settings for this command-line tool." }
        if entry.service == "kTCCServiceAppleEvents" { return "Turning off resets all Automation access for this app." }
        return "Turn off to revoke. The app will have to ask again."
    }
}

private struct FullDiskAccessPrompt: View {
    @EnvironmentObject var store: PrivacyStore

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.shield").font(.system(size: 44)).foregroundStyle(.tint)
            Text("Sectop needs Full Disk Access").font(.title3.weight(.semibold))
            Text("macOS keeps its list of app permissions in a protected database. Sectop only reads it, and it never leaves your Mac.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Text("1. Click **Open Settings** below.")
                Text("2. Click **+** and choose Sectop (shown in Finder), or drag it into the list.")
                Text("3. Turn it on, then come back here.")
            }
            .font(.callout)
            HStack {
                Button("Open Settings") {
                    SystemSettings.privacy("Privacy_AllFiles")
                    NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                }
                .buttonStyle(.borderedProminent)
                Button("Check again") { store.refresh() }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension AppResolver {
    func info(for entry: TCCEntry) -> AppInfo {
        entry.clientType == 0 ? info(bundleID: entry.client) : info(path: entry.client)
    }
}

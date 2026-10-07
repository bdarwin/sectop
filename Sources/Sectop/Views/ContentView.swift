import SwiftUI

enum Tab: String, CaseIterable, Identifiable {
    case privacy = "Privacy", startup = "Startup", sharing = "Sharing", network = "Network"
    var id: Self { self }
}

struct ContentView: View {
    @EnvironmentObject var live: LiveMonitor
    @EnvironmentObject var privacy: PrivacyStore
    @EnvironmentObject var startup: StartupStore
    @EnvironmentObject var sharing: SharingStore
    @EnvironmentObject var network: NetworkStore
    @AppStorage("tab") private var tab: Tab = .privacy

    var body: some View {
        VStack(spacing: 0) {
            header
            if live.anyInUse { LiveBanner() }
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            Group {
                switch tab {
                case .privacy: PrivacyView()
                case .startup: StartupView()
                case .sharing: SharingView()
                case .network: NetworkView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            FooterView()
        }
        .frame(width: 460, height: 640)
        .onAppear { refresh(tab) }
        .onChange(of: tab) { _, new in refresh(new) }
    }

    private var header: some View {
        HStack {
            Image(systemName: "lock.shield.fill").foregroundStyle(.tint)
            Text("Sectop").font(.headline)
            Spacer()
            Button { refresh(tab) } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .help("Refresh")
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }

    private func refresh(_ tab: Tab) {
        switch tab {
        case .privacy: privacy.refresh()
        case .startup: startup.refresh()
        case .sharing: sharing.refresh()
        case .network: network.refresh()
        }
    }
}

struct LiveBanner: View {
    @EnvironmentObject var live: LiveMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if live.cameraInUse {
                Label("Camera is on", systemImage: "video.fill")
            }
            if live.micInUse {
                Label(micText, systemImage: "mic.fill")
            }
        }
        .font(.callout.weight(.medium))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.gradient))
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private var micText: String {
        let names = live.micApps.map(\.name)
        return names.isEmpty ? "Microphone is on" : "Microphone in use by " + names.joined(separator: ", ")
    }
}

struct FooterView: View {
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        HStack {
            Toggle("Open at login", isOn: $launchAtLogin)
                .toggleStyle(.checkbox)
                .onChange(of: launchAtLogin) { _, on in LaunchAtLogin.set(on) }
            Spacer()
            Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")")
                .foregroundStyle(.tertiary)
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Shared bits

struct IconView: View {
    let image: NSImage
    var size: CGFloat = 22
    var body: some View {
        Image(nsImage: image).resizable().interpolation(.high).frame(width: size, height: size)
    }
}

struct MessageBar: View {
    @Binding var message: String?
    var body: some View {
        if let text = message {
            HStack(alignment: .top) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button { message = nil } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
            }
            .padding(8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 12)
            .padding(.top, 6)
        }
    }
}

struct EmptyState: View {
    let symbol: String
    let text: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.largeTitle).foregroundStyle(.tertiary)
            Text(text).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A switch that shows a spinner while a change is applying.
struct BusySwitch: View {
    let isOn: Bool
    let busy: Bool
    let action: (Bool) -> Void
    var body: some View {
        if busy {
            ProgressView().controlSize(.small).frame(width: 32)
        } else {
            Toggle("", isOn: Binding(get: { isOn }, set: action))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
    }
}

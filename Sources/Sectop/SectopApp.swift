import SwiftUI

@main
struct SectopApp: App {
    @StateObject private var live = LiveMonitor()
    @StateObject private var privacy = PrivacyStore()
    @StateObject private var startup = StartupStore()
    @StateObject private var sharing = SharingStore()
    @StateObject private var network = NetworkStore()

    init() {
        if CommandLine.arguments.contains("--diagnose") {
            Diagnose.run()
            exit(0)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(live)
                .environmentObject(privacy)
                .environmentObject(startup)
                .environmentObject(sharing)
                .environmentObject(network)
        } label: {
            Image(systemName: live.cameraInUse ? "video.fill" : live.micInUse ? "mic.fill" : "lock.shield")
        }
        .menuBarExtraStyle(.window)
    }
}

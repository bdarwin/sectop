import Foundation

/// `Sectop.app/Contents/MacOS/Sectop --diagnose` prints what the app sees, for bug reports.
enum Diagnose {
    static func run() {
        print("== Live")
        print("mic:", AudioProbe.processesUsingInput().map { "\($0.count) process(es) \($0.map(\.bundleID))" } ?? "n/a",
              "| any input device running:", AudioProbe.anyInputDeviceRunning(),
              "| camera:", CameraProbe.anyCameraRunning())

        print("== Privacy (TCC)")
        for scope in [TCCScope.user, .system] {
            do {
                let rows = try TCC.read(scope)
                print("\(scope): \(rows.count) entries, \(rows.filter(\.isAllowed).count) allowed")
            } catch {
                print("\(scope): \(error)")
            }
        }

        print("== Startup")
        for item in LaunchItems.scan() {
            print(item.enabled ? "on " : "off", item.loaded ? "loaded" : "      ", item.domain, item.label)
        }

        print("== Sharing")
        for s in SharingService.all { print(SharingService.isOn(s) ? "on " : "off", s.name) }

        print("== Network")
        for p in Network.scan().prefix(15) {
            print(p.pid, p.command, "remotes:\(p.remotes.count)", "listening:\(p.listening)")
        }
    }
}

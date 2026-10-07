import AppKit

struct AppInfo {
    let name: String
    let icon: NSImage
    let url: URL?
}

/// Resolves bundle IDs and executable paths to a display name and icon, with caching.
@MainActor
final class AppResolver {
    static let shared = AppResolver()
    private var cache: [String: AppInfo] = [:]
    private let genericApp = NSWorkspace.shared.icon(for: .application)
    private let genericExec = NSWorkspace.shared.icon(for: .unixExecutable)

    func info(bundleID: String) -> AppInfo {
        if let hit = cache["b:" + bundleID] { return hit }
        let info: AppInfo
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            info = AppInfo(name: Self.displayName(url), icon: NSWorkspace.shared.icon(forFile: url.path), url: url)
        } else {
            info = AppInfo(name: bundleID, icon: genericApp, url: nil)
        }
        cache["b:" + bundleID] = info
        return info
    }

    /// For an executable path, prefer the outermost enclosing .app so helpers group under their app.
    func info(path: String) -> AppInfo {
        if let hit = cache["p:" + path] { return hit }
        let info: AppInfo
        if let range = path.range(of: ".app/") ?? (path.hasSuffix(".app") ? path.range(of: ".app", options: .backwards) : nil) {
            let url = URL(fileURLWithPath: String(path[..<range.lowerBound]) + ".app")
            info = AppInfo(name: Self.displayName(url), icon: NSWorkspace.shared.icon(forFile: url.path), url: url)
        } else if FileManager.default.fileExists(atPath: path) {
            info = AppInfo(name: (path as NSString).lastPathComponent, icon: genericExec, url: URL(fileURLWithPath: path))
        } else {
            info = AppInfo(name: (path as NSString).lastPathComponent, icon: genericExec, url: nil)
        }
        cache["p:" + path] = info
        return info
    }

    private static func displayName(_ url: URL) -> String {
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}

enum SystemSettings {
    static func open(_ url: String) {
        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
    }
    static func privacy(_ anchor: String?) {
        open("x-apple.systempreferences:com.apple.preference.security" + (anchor.map { "?" + $0 } ?? ""))
    }
    static let loginItems = "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
    static let sharing = "x-apple.systempreferences:com.apple.Sharing-Settings.extension"
    static let location = "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
}

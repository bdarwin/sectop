import Foundation
import SQLite3

/// A privacy permission category as stored in the TCC database.
struct TCCService {
    let key: String
    let name: String
    let symbol: String
    let anchor: String?

    var tccutilName: String { key.hasPrefix("kTCCService") ? String(key.dropFirst("kTCCService".count)) : key }
    var isKnown: Bool { Self.catalog[key] != nil }

    static func named(_ key: String) -> TCCService {
        catalog[key] ?? TCCService(key: key, name: String(key.dropFirst(key.hasPrefix("kTCCService") ? 11 : 0)),
                                   symbol: "questionmark.circle", anchor: nil)
    }

    /// Display order for known services.
    static let order: [String] = [
        "kTCCServiceCamera", "kTCCServiceMicrophone", "kTCCServiceScreenCapture", "kTCCServiceAccessibility",
        "kTCCServiceSystemPolicyAllFiles", "kTCCServiceListenEvent", "kTCCServicePostEvent", "kTCCServiceAppleEvents",
        "kTCCServiceSystemPolicyAppBundles", "kTCCServiceSystemPolicyAppData", "kTCCServiceAddressBook",
        "kTCCServiceCalendar", "kTCCServiceReminders", "kTCCServicePhotos", "kTCCServicePhotosAdd",
        "kTCCServiceSystemPolicyDesktopFolder", "kTCCServiceSystemPolicyDocumentsFolder",
        "kTCCServiceSystemPolicyDownloadsFolder", "kTCCServiceSystemPolicyNetworkVolumes",
        "kTCCServiceSystemPolicyRemovableVolumes", "kTCCServiceFileProviderDomain", "kTCCServiceBluetoothAlways",
        "kTCCServiceSpeechRecognition", "kTCCServiceMediaLibrary", "kTCCServiceDeveloperTool",
        "kTCCServiceFocusStatus", "kTCCServiceWillow", "kTCCServiceUserTracking",
    ]

    static let catalog: [String: TCCService] = {
        let list: [(String, String, String, String?)] = [
            ("Camera", "Camera", "video.fill", "Privacy_Camera"),
            ("Microphone", "Microphone", "mic.fill", "Privacy_Microphone"),
            ("ScreenCapture", "Screen Recording", "record.circle", "Privacy_ScreenCapture"),
            ("Accessibility", "Accessibility (control your Mac)", "accessibility", "Privacy_Accessibility"),
            ("SystemPolicyAllFiles", "Full Disk Access", "internaldrive.fill", "Privacy_AllFiles"),
            ("ListenEvent", "Input Monitoring (keystrokes)", "keyboard", "Privacy_ListenEvent"),
            ("PostEvent", "Send Keystrokes", "keyboard.badge.ellipsis", "Privacy_Accessibility"),
            ("AppleEvents", "Automation (control other apps)", "gearshape.2.fill", "Privacy_Automation"),
            ("SystemPolicyAppBundles", "App Management", "app.badge", "Privacy_AppBundles"),
            ("SystemPolicyAppData", "Other Apps' Data", "tray.full", "Privacy_AppData"),
            ("AddressBook", "Contacts", "person.crop.circle", "Privacy_Contacts"),
            ("Calendar", "Calendars", "calendar", "Privacy_Calendars"),
            ("Reminders", "Reminders", "checklist", "Privacy_Reminders"),
            ("Photos", "Photos", "photo", "Privacy_Photos"),
            ("PhotosAdd", "Add to Photos", "photo.badge.plus", "Privacy_Photos"),
            ("SystemPolicyDesktopFolder", "Desktop Folder", "menubar.dock.rectangle", "Privacy_FilesAndFolders"),
            ("SystemPolicyDocumentsFolder", "Documents Folder", "doc.fill", "Privacy_FilesAndFolders"),
            ("SystemPolicyDownloadsFolder", "Downloads Folder", "arrow.down.circle.fill", "Privacy_FilesAndFolders"),
            ("SystemPolicyNetworkVolumes", "Network Volumes", "network", "Privacy_FilesAndFolders"),
            ("SystemPolicyRemovableVolumes", "Removable Volumes", "externaldrive.fill", "Privacy_FilesAndFolders"),
            ("FileProviderDomain", "File Provider Files", "folder.fill", "Privacy_FilesAndFolders"),
            ("BluetoothAlways", "Bluetooth", "dot.radiowaves.left.and.right", "Privacy_Bluetooth"),
            ("SpeechRecognition", "Speech Recognition", "waveform", "Privacy_SpeechRecognition"),
            ("MediaLibrary", "Media & Apple Music", "music.note", "Privacy_Media"),
            ("DeveloperTool", "Developer Tools", "hammer.fill", "Privacy_DevTools"),
            ("FocusStatus", "Focus", "moon.fill", "Privacy_Focus"),
            ("Willow", "Home", "house.fill", "Privacy_HomeKit"),
            ("UserTracking", "Tracking", "hand.raised.fill", "Privacy_Advertising"),
        ]
        return Dictionary(uniqueKeysWithValues: list.map { key, name, symbol, anchor in
            let full = "kTCCService" + key
            return (full, TCCService(key: full, name: name, symbol: symbol, anchor: anchor))
        })
    }()
}

enum TCCScope: String { case user, system }

struct TCCEntry: Identifiable, Hashable {
    let service: String
    let client: String
    /// 0 = bundle identifier, 1 = absolute path.
    let clientType: Int
    /// 0 = denied, 2 = allowed, 3 = limited.
    let authValue: Int
    let indirect: String
    let lastModified: Date
    let scope: TCCScope

    var id: String { "\(scope.rawValue)|\(service)|\(client)|\(indirect)" }
    var isAllowed: Bool { authValue == 2 || authValue == 3 }
    var isLimited: Bool { authValue == 3 }
    var info: TCCService { TCCService.named(service) }
    var automationTarget: String? {
        service == "kTCCServiceAppleEvents" && !indirect.isEmpty && indirect != "UNUSED" ? indirect : nil
    }
}

enum TCC {
    static let userDB = NSHomeDirectory() + "/Library/Application Support/com.apple.TCC/TCC.db"
    static let systemDB = "/Library/Application Support/com.apple.TCC/TCC.db"

    enum ReadError: Error { case noAccess, failed(String) }

    static func read(_ scope: TCCScope) throws -> [TCCEntry] {
        try read(path: scope == .user ? userDB : systemDB, scope: scope)
    }

    static func read(path: String, scope: TCCScope) throws -> [TCCEntry] {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw classify(db)
        }
        let sql = """
            SELECT service, client, client_type, auth_value, IFNULL(indirect_object_identifier, ''), IFNULL(last_modified, 0)
            FROM access
            """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw classify(db) }

        var entries: [TCCEntry] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw classify(db) }
            entries.append(TCCEntry(
                service: text(stmt, 0),
                client: text(stmt, 1),
                clientType: Int(sqlite3_column_int(stmt, 2)),
                authValue: Int(sqlite3_column_int(stmt, 3)),
                indirect: text(stmt, 4),
                lastModified: Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 5))),
                scope: scope))
        }
        return entries
    }

    private static func text(_ stmt: OpaquePointer?, _ col: Int32) -> String {
        sqlite3_column_text(stmt, col).map { String(cString: $0) } ?? ""
    }

    private static func classify(_ db: OpaquePointer?) -> ReadError {
        let code = sqlite3_errcode(db)
        let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
        if code == SQLITE_AUTH || code == SQLITE_CANTOPEN || code == SQLITE_PERM || msg.contains("authorization denied") {
            return .noAccess
        }
        return .failed(msg)
    }

    /// Revokes a permission by resetting it, so the app has to ask again.
    /// macOS doesn't let third-party apps grant permissions, only reset them.
    /// Returns nil on success (or user cancel), else a message.
    static func revoke(_ entry: TCCEntry) -> String? {
        guard entry.clientType == 0 else { return "Path-based clients can only be changed in System Settings." }
        let svc = entry.info.tccutilName
        Shell.run("/usr/bin/tccutil", ["reset", svc, entry.client])
        if !stillGranted(entry) { return nil }

        // System-wide permissions (Accessibility, Full Disk Access...) need root.
        let r = Shell.runAsAdmin("/usr/bin/tccutil reset \(Shell.quote(svc)) \(Shell.quote(entry.client))")
        if r.cancelled { return nil }
        if !r.ok { return r.err.trimmingCharacters(in: .whitespacesAndNewlines) }
        return stillGranted(entry) ? "macOS kept this permission. Turn it off in System Settings instead." : nil
    }

    private static func stillGranted(_ entry: TCCEntry) -> Bool {
        guard let rows = try? read(entry.scope) else { return false }
        return rows.contains { $0.service == entry.service && $0.client == entry.client && $0.isAllowed }
    }
}

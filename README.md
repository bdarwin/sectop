# Sectop

**See who has access to what on your Mac, and switch it off from the menu bar.**

Sectop is a small, native menu bar app for macOS 14+ that shows all of these in one place:

| Tab | What you see | What you can do |
|---|---|---|
| **Live** (banner) | Camera on, mic on and *which app* is using the mic | – |
| **Privacy** | Every app's permissions: Camera, Microphone, Screen Recording, Accessibility, Full Disk Access, Input Monitoring, Automation, Contacts, Photos, Files & Folders… grouped by app or by permission | Revoke with one switch |
| **Startup** | Launch agents & daemons that start with your Mac | Enable / disable |
| **Sharing** | Remote Login (SSH), Screen Sharing, File Sharing, Remote Apple Events | Turn on / off |
| **Network** | Which of your apps have open internet connections or listening ports | Quit the process |

The menu bar icon changes to 🎥 / 🎙 while the camera or microphone is live.

## Install

### Download
1. Get the latest `Sectop-x.y.z.dmg` from [Releases](https://github.com/bdarwin/sectop/releases).
2. Open it and drag **Sectop** to **Applications**.
3. Sectop isn't notarized yet, so macOS will block the first launch. Either:
   - open it once, then go to **System Settings → Privacy & Security** and click **Open Anyway**, or
   - run `xattr -dr com.apple.quarantine /Applications/Sectop.app`.

### Build from source
Requires Xcode 15+ (Swift 5.10+).
```sh
git clone https://github.com/bdarwin/sectop && cd sectop
./scripts/build-app.sh        # → dist/Sectop.app (universal)
./scripts/make-dmg.sh         # → dist/Sectop-<version>.dmg
```

## Permissions Sectop needs

- **Full Disk Access.** macOS stores the permission list in a protected database (`TCC.db`). Sectop only *reads* it, and nothing leaves your Mac. The app walks you through granting it.
- **Admin password**, only when you change system-wide items: system daemons, sharing services, or system-level permissions like Accessibility. It uses the standard macOS prompt.

## How switches work (and macOS limits)

- **Turning a permission off** runs `tccutil reset`, the Apple-supported way to revoke. The app has to ask again next time.
- **Turning a permission on** can't be done by any third-party app. Apple deliberately blocks it. Sectop opens the exact System Settings pane instead.
- Turning off **Automation** for an app resets all of its Automation targets (a `tccutil` limitation).
- **Location Services** are root-only, so Sectop links to the System Settings pane.
- The **Network** tab shows your own processes. System processes need root to inspect.
- Ad-hoc signed builds change signature on every update, so you may need to re-grant Full Disk Access after updating.

## Troubleshooting

```sh
/Applications/Sectop.app/Contents/MacOS/Sectop --diagnose
```
prints everything Sectop can see. Include it in bug reports (check it for anything private first).

## Roadmap

- Developer ID signing + notarization, Homebrew cask, Sparkle auto-updates
- Notifications when an app gains a new permission or a new login item appears
- Location Services and full Login Items (BTM) listing via a privileged helper
- Per-app network blocking (Network Extension)

## License

MIT

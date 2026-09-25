# Q-Dock

A floating, pinnable dock for macOS, with a copy on every screen.

- Pin to any screen edge or float anywhere; each screen positions independently (or sync them)
- Instant hover labels with a small genie magnification
- Folder stacks as **Fan** or **Grid**: drag files out, drop files in, right-click to Copy / Rename / Move to Trash
- Separator + running-but-unpinned apps, Trash, Force Quit
- Icon size and spacing, Lock Position, Dock Mode (keeps windows out from behind an edge-pinned dock)

## Build & install

```bash
./build.sh
rm -rf ~/Applications/Q-Dock.app && cp -R Q-Dock.app ~/Applications/ && open ~/Applications/Q-Dock.app
```

Requires Xcode (uses `xcrun swiftc`), macOS 14+. The app is ad-hoc signed, so macOS asks for
Accessibility permission (Dock Mode) again after each rebuild.

Settings live in `defaults read com.local.qdock`.

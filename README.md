<p align="center">
  <img src="assets/icon.png" width="112" alt="Q-Dock icon">
</p>

<h1 align="center">Q-Dock</h1>

<p align="center">
  A floating, pinnable dock for macOS — one on every screen, each positioned on its own.
</p>

<p align="center">
  <a href="https://github.com/cyber-qais/qais-mac-dock/releases/latest"><b>⬇︎ Download the latest release</b></a>
</p>

<p align="center">
  <img src="docs/screenshots/dock-horizontal.png" alt="Q-Dock pinned horizontally, with pinned apps, folders, a separator, running apps and the Trash">
</p>

---

The macOS Dock lives on one edge of one screen. **Q-Dock** puts a dock on *every* display and lets you
pin each one to any edge, or float it anywhere. It's a single native Swift file with no dependencies.

## Sound familiar?

If you use more than one monitor, the macOS Dock probably gets in your way.

| 😤 The macOS Dock… | ✅ Q-Dock… |
|---|---|
| **Jumps to another screen.** Nudge your pointer against the bottom of a different monitor and the Dock moves there, whether you meant it to or not. | **Stays where you put it.** Every screen has its own dock, and **Lock Position** keeps it from moving at all. |
| **Only lives on one screen.** Your other monitors don't get a Dock, so you drag the pointer back across the desk to launch anything. | **Is on every screen.** Each display gets a full dock with all your apps, folders and the Trash. |
| **Only goes on the bottom, left or right,** always centered. Never the top, and never where you'd actually like it. | **Goes anywhere.** Pin it to any edge (including the **top**), slide it along that edge, or float it anywhere, horizontally or vertically. |
| **Has one position for every screen.** A layout that suits your laptop can't differ from the one on your ultrawide. | **Has a position per screen.** Top edge on one monitor, bottom on another, floating on a third. |
| **Plays hide-and-seek with windows.** With auto-hide on, it pops up over whatever you're working on. Windows you've dragged or resized by hand end up tucked under it. | **Keeps windows out of the way.** Turn on **Dock Mode** and windows that slide under the dock get nudged or resized so they stay clear. |
| **Shrinks your icons** as you pin more apps, until they're too small to tell apart. | **Wraps** onto another row or column instead, at the icon size and spacing you chose. |

## Features

| | |
|---|---|
| 🖥️ **Every screen** | A dock on each display, each with its own position, icon size, spacing and options, or shared settings everywhere. |
| 📌 **Pin anywhere** | Snap to the left, right, top or bottom edge, or float it anywhere (vertical or horizontal). |
| 🔒 **Lock Position** | Freeze it in place. The ⋮⋮ grip disappears until you unlock. |
| 🙈 **Hide the macOS Dock** | Optional. Keeps the built-in Dock out of sight so only Q-Dock shows, and brings it back when Q-Dock quits if you want. |
| 🫥 **Auto-Hide** | Per screen. The dock slides off its edge and comes back when you push the pointer against that edge. Toggle it with **⌃⌥D**. |
| 🪟 **Dock Mode** | Keeps other windows out from behind an edge-pinned dock by nudging or resizing them. |
| 🏷️ **Instant labels** | App names appear the moment you hover, with a small genie-style magnification. |
| 📂 **Folder stacks** | Open folders as a **Fan** or **Grid**, with previews. Drag files out, drop files in, and right-click to copy, rename or trash. |
| ⚙️ **Running apps** | Open apps that aren't pinned show up after a separator. Drag one in to pin it. |
| 🗑️ **Trash** | Shows empty or full. Drop files on it to trash them, or drop a dock icon on it to remove it. |
| 🎨 **Folder icons** | Give each docked folder its own color, a symbol (⭐️, 📷, </>, …) or any image or app icon. |
| ➗ **Separators & spacers** | Group your apps with separators, spacers and small spacers, placed anywhere. |
| ⬆️ **One-click updates** | Q-Dock tells you when a new version is out and can update and restart itself. |
| 📏 **Density** | Icon sizes from Tiny to Huge and spacing from Tight to Roomy. Long docks wrap onto more rows. |
| 🧭 **Setup assistant** | A first-launch walkthrough for permissions and the basics. |

## Install

### Download

1. Download **Q-Dock.zip** from the [latest release](https://github.com/cyber-qais/qais-mac-dock/releases/latest) and unzip it.
2. Move **Q-Dock.app** into your Applications folder.
3. Open it. Q-Dock isn't notarized by Apple, so the first time you open it, **right-click → Open**, then click
   **Open** again (or go to System Settings → Privacy & Security → **Open Anyway**). If macOS says the app is
   "damaged", run:

   ```bash
   xattr -dr com.apple.quarantine /Applications/Q-Dock.app
   ```

Runs on macOS 14 or later, on both Apple Silicon and Intel Macs.

### Build from source

Requires macOS 14 or later and Xcode (or the Xcode Command Line Tools).

```bash
git clone https://github.com/cyber-qais/qais-mac-dock.git
cd qais-mac-dock
tools/make-signing-cert.sh   # optional, once: keeps permissions across rebuilds
./build.sh
cp -R Q-Dock.app ~/Applications/
open ~/Applications/Q-Dock.app
```

On first launch, Q-Dock imports the items from your macOS Dock and opens the setup assistant.
The Q-Dock icon in the menu bar opens settings at any time.

### Updating

```bash
git pull && ./build.sh
pkill -x Q-Dock; rm -rf ~/Applications/Q-Dock.app && cp -R Q-Dock.app ~/Applications/ && open ~/Applications/Q-Dock.app
```

> [!NOTE]
> **Keep permissions across rebuilds:** run `tools/make-signing-cert.sh` once. It creates a self-signed
> "Q-Dock Local Signing" certificate in your login keychain, and `build.sh` signs with it automatically.
> Without it, builds are ad-hoc signed, and macOS treats every rebuild as a new app, so you'd have to allow
> **Accessibility** (and **Full Disk Access**) again each time.

## Using Q-Dock

### Move and pin it

<img src="docs/screenshots/dock-vertical.png" align="right" height="420" alt="Q-Dock pinned vertically, wrapping onto a second column">

- **Drag the ⋮⋮ grip** (or any empty spot on the dock).
  - Drop it **within ~60 pt of a screen edge** and it snaps to that edge.
  - Drop it **anywhere else** and it floats there.
- Or right-click the dock → **Position** → *Left / Right / Top / Bottom Edge* or *Floating*.
  A floating dock can be switched between **Vertical** and horizontal.
- **Each screen is independent.** Right-click the dock on a screen to move just that one. To keep
  them in sync, turn on **Same Position on Every Screen**.
- Turn on **Lock Position** once it's where you want it.
- If a dock gets too long for its edge, it wraps onto another row or column (right).

<br clear="right">

<p align="center">
  <img src="docs/screenshots/hover-label.png" width="209" alt="Instant hover label over the Terminal icon">
</p>
<p align="center"><sub>App names appear the moment you hover.</sub></p>

### Add, arrange and remove

| To… | Do this |
|---|---|
| Add an app, file or folder | Drag it from Finder onto the dock, or use **Add Apps or Files…** |
| Reorder | Drag an icon along the dock |
| Remove | Drag the icon off the dock, or drop it on the Trash, or right-click → **Remove from Dock** |
| Add a separator or spacer | Right-click an icon → **Insert After This** → *Separator / Spacer / Small Spacer*, or right-click the dock → **Add Separator or Spacer**. Drag it to move it; drag it off to remove it. |
| Pin a running app | Drag it from the running section into the pinned area, or right-click → **Keep in Dock** |
| Open a file with a specific app | Drop the file onto that app's icon |
| Quit an app | Right-click → **Quit**, or **Force Quit** (no ⌥ needed) |

### Folders: Fan and Grid

Click a docked folder to open it as a stack. Right-click the folder to pick how it opens:

- **Display As** → **Fan**, **Grid**, or **Folder** (open it in Finder)
- **Sort By** → Name, Date Added, Date Modified, Date Created or Kind

<p align="center">
  <img src="docs/screenshots/folder-grid.png" width="327" alt="A folder opened as a Grid stack">
  &nbsp;&nbsp;
  <img src="docs/screenshots/file-context-menu.png" width="365" alt="Right-click menu on a file inside a stack">
</p>

Inside an open stack:

- **Click** a file to open it.
- **Drag** a file out into Finder, an email or any other app.
- **Right-click** a file for **Open**, **Open Folder**, **Copy**, **Copy Path**, **Rename…** or **Move to Trash**.

**Folder icons:** right-click a docked folder → **Folder Icon** to pick a **Color**, a **Symbol**, or a
**Custom Image…** (any image, `.icns` file or app). **Reset to Default** puts the normal folder back.

To move files **into** a folder, drop them onto its dock icon. Files on the same drive are moved and
files from another drive are copied, as in Finder. Hold **⌥** to always copy. If a name is already
taken, the new file gets a number added (`report 2.pdf`).

### Auto-Hide

Right-click the dock → **Auto-Hide (this screen)**, or press **⌃⌥D** with the pointer on that screen.

- The dock slides off its edge half a second after the pointer leaves it.
- **Push the pointer against that edge** for a moment to bring it back.
- It stays visible while a folder stack or menu is open, or while you're dragging.
- It's set per screen, so you can hide the dock on your laptop screen and keep it on your big monitor.
- It works on docks pinned to an edge. A floating dock doesn't auto-hide.
- An auto-hidden dock doesn't reserve space in Dock Mode, so windows can use the whole screen.

### Hiding the macOS Dock

Q-Dock asks once (in the setup assistant) whether to hide the built-in Dock. You can change it anytime from the menu:
**Hide macOS Dock** and **Bring Back macOS Dock When Q-Dock Quits**.

The macOS Dock can't be quit, because the same process runs ⌘-Tab, Mission Control and Spaces. Instead, Q-Dock
turns on its auto-hide with a very long delay, so it never appears. Your original Dock settings are saved and put
back when you turn the option off (or when Q-Dock quits, if you chose that).

To bring it back by hand:

```bash
defaults delete com.apple.dock autohide-delay; defaults write com.apple.dock autohide -bool false; killall Dock
```

### Dock Mode

Turn on **Dock Mode** to keep windows from sitting behind an edge-pinned dock. When a window overlaps the
dock, Q-Dock shrinks it (or moves it if it's small) so it stays clear. It skips full-screen windows and
does nothing for a floating dock.

Dock Mode also keeps **desktop icons** clear. Finder doesn't know about Q-Dock, so a file you drop, a new
screenshot or a download can land under the dock. Every few seconds, Q-Dock moves any desktop icon that's under
an edge-pinned dock to just past it. (If your desktop uses **Sort By**, Finder arranges the icons itself and
won't let them be moved.)

macOS has no public way for an app to reserve screen space. So Dock Mode uses the Accessibility API for windows,
which needs **Accessibility** permission, and Finder scripting for desktop icons, which macOS asks you to allow once.

## Updates

Q-Dock checks GitHub for a new release when it starts and once a day. When there is one, it shows what's new
and offers **Update & Restart**, **Later** or **Skip This Version**. **Update & Restart** downloads the new
version, checks that it's signed with the same certificate as the running app, swaps it in and relaunches.
Your settings and permissions carry over.

- **Check for Updates…** in the menu checks right away. Turn off **Check for Updates Automatically** to stop the daily check.
- If Q-Dock can't replace itself (for example, it's in a folder you can't write to), it opens the download page instead.
- Builds you make yourself won't take updates from GitHub, because they're signed with a different certificate.
  Update those with `git pull && ./build.sh`.

## Settings

<img src="docs/screenshots/dock-menu.png" align="right" width="300" alt="Q-Dock's right-click menu">

Everything is in the right-click menu (right) and the menu-bar icon.

**Each screen can have its own settings.** Right-click a dock to change settings under **This Screen**, which
covers position, icon size, spacing, Lock Position, Auto-Hide, Dock Mode, Keep Above Other Windows, Show Running Apps
and Show Trash. The menu-bar icon changes the same settings for **All Screens** at once. A screen with its own
settings shows **Use Shared Settings on This Screen** to go back to the shared ones. Pinned items, **Hide macOS
Dock**, **Launch at Login** and updates apply everywhere.

<br clear="right">

The defaults (shared by every screen until a screen sets its own) are:

| Setting | Default | Options |
|---|---|---|
| Position | Main screen: top edge · other screens: bottom edge | Left, Right, Top, Bottom, Floating |
| Icon Size | Small (32 pt) | Tiny 28 · Small 32 · Medium-Small 40 · Medium 48 · Medium-Large 56 · Large 64 · Huge 80 |
| Icon Spacing | Tight (0) | Tight 0 · Compact 2 · Normal 6 · Roomy 12 |
| Lock Position | On | |
| Hide macOS Dock | Off (you're asked during setup) | Bring it back when Q-Dock quits: On |
| Auto-Hide | Off | Per screen · ⌃⌥D toggles it on the screen under the pointer |
| Dock Mode | On (once Accessibility is allowed) | |
| Keep Above Other Windows | On | |
| Show Running Apps | On | |
| Show Trash | On | |
| Show on All Screens | On | |
| Same Position on Every Screen | Off | |
| Launch at Login | Off | |
| Check for Updates Automatically | On | |

### Scripting settings

Settings are stored in the `com.local.qdock` defaults domain, so you can script them. Quit Q-Dock
first, change the settings, then relaunch:

```bash
pkill -x Q-Dock

# Bigger icons with a little breathing room
defaults write com.local.qdock iconSize -float 48
defaults write com.local.qdock spacing -float 6

# Unlock and turn off Dock Mode
defaults write com.local.qdock locked -bool false
defaults write com.local.qdock dockMode -bool false

# Replace the pinned items
defaults write com.local.qdock items -array \
  "/System/Library/CoreServices/Finder.app" \
  "/Applications/Safari.app" \
  "$HOME/Downloads"

open ~/Applications/Q-Dock.app
```

```bash
# See everything
defaults read com.local.qdock

# Start over (re-imports your macOS Dock and shows the setup assistant again)
pkill -x Q-Dock; defaults delete com.local.qdock; open ~/Applications/Q-Dock.app
```

## Permissions

| Permission | Used for | Where to allow it |
|---|---|---|
| Accessibility | Dock Mode (moving other windows) | System Settings → Privacy & Security → Accessibility |
| Full Disk Access | The Trash full/empty icon; opening protected folders as stacks | System Settings → Privacy & Security → Full Disk Access |
| Automation (Finder) | Keeping desktop icons clear in Dock Mode; **Empty Trash…** | macOS asks the first time it's needed |

The setup assistant opens on first launch, and you can reopen it anytime from **Setup Assistant…** in the menu.
It shows live status for each permission and links to the right Settings page.

![The three steps of the setup assistant: Welcome, Permissions and The basics](docs/screenshots/setup-assistant.png)

## Project layout

```
main.swift               the whole app (AppKit + a SwiftUI setup assistant)
build.sh                 compiles, generates the icon, and bundles Q-Dock.app
tools/make-icon.swift    turns assets/icon.png into AppIcon.icns
tools/make-signing-cert.sh  creates the local signing certificate build.sh uses
assets/icon.png          app icon source
docs/screenshots/        images used in this README
```

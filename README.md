# Perch

A personal, unsandboxed, self-signed Yoink-style drag-and-drop **shelf** for macOS.

Drag anything onto a screen-edge tab, Perch holds it, and you drag it back out later —
into any destination app. File promises work in both directions, so sources and
destinations that only speak promises (Photos, Mail, Messages) keep working, and the
source app doesn't have to still be running when you drop.

## Run

For quick iteration:

```sh
swift build
swift run
```

Perch runs as an **accessory** app — no Dock icon, no menu bar item
(`NSApp.setActivationPolicy(.accessory)`). Requires macOS 14+.

## Install as an app (always-on)

To use Perch day-to-day, build a real `.app` bundle and have it launch at login:

```sh
swift Scripts/make-icon.swift   # one-time: generates Resources/AppIcon.icns
./Scripts/build-app.sh          # builds + ad-hoc-signs Perch.app
mv Perch.app /Applications      # a stable location keeps the login item valid
open /Applications/Perch.app
```

Then right-click the shelf and turn on **Launch at Login** (it appears only when running
as a bundled app, and uses `SMAppService`). Since the shelf has no Dock or menu-bar
presence, **Quit Perch** also lives in that right-click menu.

### Updating after a code change

The installed app does **not** auto-update — it's a snapshot. After editing the source,
rebuild and reinstall in one step:

```sh
./Scripts/install.sh   # rebuilds Perch.app, quits the running copy, reinstalls, relaunches
```

It replaces `/Applications/Perch.app` in place, so the Dock launcher keeps working. (If
Launch at Login ever stops firing after an update, toggle it off then on once — the
ad-hoc signature changes each build.)

## Use it

- **Stash:** start dragging anything; a tab appears on the nearest screen edge (and on the
  notch). Drag over it and the shelf slides out — drop onto it to store.
- **Retrieve:** hover the edge to reveal the shelf, then drag an item out into any app.
  Items move out by default (the shelf hands off its copy).
- **Reorder:** drag a row up/down *within* the shelf to rearrange; drag it *out* to vend.
- **Right-click** an item or the shelf for: **Quick Look**, **Delete**, **Clear All**, and
  **Appearance ▸ Glass / Minimal** (toggles the look live; the choice persists).
- **Hover** a row (Glass) to reveal a **✕** delete button.

The card sizes itself to its contents — small with one item, growing as you add more.

## Data

Everything lives under `~/Library/Application Support/Perch/`:

```
index.json          # ordered item list (display order)
items/<uuid>/
  meta.json         # item metadata
  reps/rep-N.dat    # raw pasteboard representations
  files/            # copied real files + materialized promises
```

It's plain JSON + files on disk — inspectable and easy to delete.

## License

[MIT](LICENSE) © Maximilian Reich

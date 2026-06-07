# Perch

A personal, unsandboxed, self-signed Yoink-style drag-and-drop **shelf** for macOS.

Drag anything onto a screen-edge tab, Perch holds it, and you drag it back out later —
into any destination app. File promises work in both directions, so sources and
destinations that only speak promises (Photos, Mail, Messages) keep working, and the
source app doesn't have to still be running when you drop.

## Run

```sh
swift build
swift run
```

Perch runs as an **accessory** app — no Dock icon, no menu bar item
(`NSApp.setActivationPolicy(.accessory)`). Requires macOS 14+.

## Use it

- **Stash:** start dragging anything; a tab appears on the nearest screen edge (and on the
  notch). Drag over it and the shelf slides out — drop onto it to store.
- **Retrieve:** hover the edge to reveal the shelf, then drag an item out into any app.
  Items move out by default (the shelf hands off its copy).
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

## Docs

See [`ARCHITECTURE.md`](ARCHITECTURE.md) for the conceptual model (temporal decoupling of
source and destination), the three pipelines (receive / store / re-vend), the component
map, and the on-disk data model.

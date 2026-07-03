<p align="center">
  <img src="assets/icon.png" width="128" alt="Perch icon">
</p>

<h1 align="center">Perch</h1>

<p align="center">
  A drag-and-drop shelf for macOS.
</p>


Start dragging something and a tab snaps to the nearest screen edge. Drop onto it to stash, hover the edge to pull it back out. Works with files, text, images, URLs, and file promises from Photos, Mail, or Messages — in both directions.

<!-- TODO: add a demo GIF here -->

## Install

Grab `Perch.zip` from the [latest release](https://github.com/maxthegray/Perch/releases), unzip, and drag it to Applications.

Since it's not notarized, macOS will probably block the first launch. Right-click → Open once to get past it, or just run:

```sh
xattr -dr com.apple.quarantine /Applications/Perch.app
```

No Dock icon, no menu-bar icon — it just runs in the background. Requires macOS 14+.

## How it works

- **Stash** — start dragging anything and a tab appears on the nearest screen edge. Drop onto it.
- **Retrieve** — hover the edge to reveal the shelf, drag an item back out into any app.
- **Right-click** the shelf for Quick Look, Delete, Clear All, and settings like appearance, edges, and Launch at Login.

Everything is stored as plain files under `~/Library/Application Support/Perch/`. No network, no accounts, no tracking.

## License

[MIT](LICENSE) © Maximilian Reich

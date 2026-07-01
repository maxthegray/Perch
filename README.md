<p align="center">
  <img src="assets/icon.png" width="128" alt="Perch icon">
</p>

<h1 align="center">Perch</h1>

<p align="center">
  A free, open-source drag-and-drop shelf for macOS.
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-black?logo=apple&logoColor=white" alt="macOS 14+">
  <a href="https://github.com/maxthegray/Perch/releases"><img src="https://img.shields.io/github/v/release/maxthegray/Perch" alt="Latest release"></a>
</p>

Drag anything onto a screen-edge tab, Perch holds it, and you drag it back out later — into any app.

<!-- TODO: add a demo GIF here -->

## Install

```sh
brew tap maxthegray/tap
brew trust --cask maxthegray/tap/perch
brew install --cask perch
```

Perch is ad-hoc signed, not notarized, so macOS may block the first launch. If that happens, right-click `/Applications/Perch.app` and choose **Open** once, or run:

```sh
xattr -dr com.apple.quarantine /Applications/Perch.app
```

You can also grab `Perch.zip` from the [latest release](https://github.com/maxthegray/Perch/releases).

Runs as an accessory app: no Dock icon, no menu-bar item. Requires macOS 14+.

## Use it

- **Stash** — start dragging anything; a tab appears on the nearest screen edge. Drop onto it to store.
- **Retrieve** — hover the edge to reveal the shelf, then drag an item out into any app.
- **Right-click** for Quick Look, Delete, Clear All, Appearance, Edges, and Launch at Login.

Works with files, text, images, URLs, and file promises (Photos, Mail, Messages) — in both directions. Everything is plain files on disk under `~/Library/Application Support/Perch/`. No network, no accounts, no tracking.

## License

[MIT](LICENSE) © Maximilian Reich

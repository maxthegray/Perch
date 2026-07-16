<p align="center">
  <img src="assets/icon.png" width="128" alt="Perch icon">
</p>

<h1 align="center">Perch</h1>

<p align="center">
  A drag-and-drop shelf for macOS.
</p>

Perch gives you a small place to set things down while you work. Start dragging a file, image, link, or bit of text and the shelf appears at the edge of your screen. Drop it there, switch to another app, and drag it back out when you're ready.

It also understands file promises from apps like Photos, Mail, and Messages, so it works with the things that don't become ordinary files until you actually drop them somewhere.

<p align="center">
  <img src="assets/demo.gif" width="800" alt="Dragging a file into Perch and back out again">
</p>

## Install

1. Download `Perch.zip` from the [latest release](https://github.com/maxthegray/Perch/releases/latest).
2. Unzip it.
3. Drag `Perch.app` into your Applications folder.
4. Open Perch from Applications.

Perch requires macOS 14 or newer. It has no Dock or menu-bar icon; once launched, it quietly waits at the screen edge. You can enable Launch at Login from Settings.

## How it works

- **Put something aside.** Start dragging and Perch can open automatically at the nearest enabled edge. Drop onto the shelf to keep the item there.
- **Pick it up later.** Hover the edge to bring Perch back, then drag the item into Finder or another app. Dragging out can move the item off the shelf or leave a copy behind.
- **Bring the shelf to you.** Shake the pointer to summon Perch near the cursor. If you'd rather keep it somewhere specific, enable dragging, pull it away from the edge, and optionally lock it in place.
- **Catch recent files.** New files in Downloads or on the Desktop can appear as dimmed suggestions. Click one to bring it onto the shelf.
- **Right-click for the useful stuff.** Quick Look, Delete, Return, History, Settings, and update checks are all close at hand.

## Make it yours

Settings are split into a few simple groups:

- Choose the Glass or Minimal style, show or hide names and shadows, and adjust the shelf's width and height.
- Dock on the left, right, or beneath the notch. At least one edge always stays enabled.
- Toggle shake-to-summon, automatic drag reveals, recent-download suggestions, movable shelves, and whether an empty floating shelf stays open.
- Choose whether dragging an item out moves it or copies it.

Perch remembers these choices between launches and can check for updates through Sparkle.

## Your files stay yours

Items on the shelf are stored as ordinary files under `~/Library/Application Support/Perch/`. There are no accounts, analytics, or tracking. Perch only uses the network for automatic or manual update checks.

## License

[MIT](LICENSE) © Maximilian Reich

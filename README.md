<p align="center">
  <img src="assets/icon.png" width="128" alt="Perch icon">
</p>

<h1 align="center">Perch</h1>

<p align="center">
  A drag-and-drop shelf for macOS.
</p>

Perch gives you a small place to set things down while you work. Start dragging a file, image, link, or bit of text and the shelf appears at the edge of your screen. Drop it there, switch to another app, and drag it back out when you're ready.

It also understands file promises from apps like Photos, Mail, and Messages, so it works with the things that don't become ordinary files until you actually drop them somewhere. And while something is sitting there, you can convert or optimize an image, extract audio, work with PDFs, or zip it without opening anything else.

<p align="center">
  <img src="assets/demo.gif" width="800" alt="Dragging a file into Perch and back out again">
</p>

## Install

1. Download `Perch.zip` from the [latest release](https://github.com/maxthegray/Perch/releases/latest).
2. Unzip it.
3. Drag `Perch.app` into your Applications folder.
4. Open Perch from Applications.

The first launch shows a short welcome: the gesture that summons the shelf, where to find Settings, which screen edges it may use, and a checkbox for opening Perch at login. Dismiss it and a shelf appears at every edge you chose at once — the real one at its home edge, a still copy at each of the others — so you can see where it lives before it gets out of the way.

Perch requires macOS 14 or newer. It has no Dock or menu-bar icon; once launched, it quietly waits at the screen edge. Launch at Login can be changed later from Settings.

## How it works

- **Put something aside.** Start dragging and Perch can open automatically at the nearest enabled edge. Drop onto the shelf to keep the item there.
- **Pick it up later.** Hover the edge to bring Perch back, then drag the item into Finder or another app. Dragging out can move the item off the shelf or leave a copy behind; hold Option while dragging to copy once.
- **Bring the shelf to you.** Turn on Shake to summon and a shake of the pointer brings Perch to the cursor. If you'd rather keep it somewhere specific, enable dragging, pull it away from the edge, and optionally lock it in place. The other edges offer themselves while you drag, so you can change your mind on the way.
- **Catch recent files.** New files in Downloads or on the Desktop can appear as dimmed suggestions. Downloads that finish together collapse into a session you can expand, inspect, or add all at once. Perch offers the five most recent.
- **Change something on the way through.** The shelf's Transform menu converts or optimizes images, strips metadata, and extracts audio from video. You can arrange and merge PDFs and images, split a PDF into separate documents, or compress a selection into a ZIP.
- **Right-click for the useful stuff.** Delete, Return, transforms, and Settings are all close at hand.

## Make it yours

**General** is the short list: launch at login, the version, a button to check for updates, and which Settings you'd rather have. *Beautiful* is the default; *Ugly* puts the same preferences back into plain forms, if that's how you prefer to read them.

**File Flow** follows a file from one end to the other and puts each choice where it happens. On the way in: whether a dropped file moves into Perch's storage or stays where it already lives, whether the shelf shows itself the moment a drag begins, and whether recent downloads are offered. In the middle: whether a transform keeps the original alongside its result or replaces it. On the way out: whether dragging an item out moves it or leaves a copy. (Choose Ugly and these same switches go back to living in General and Advanced.)

**Advanced** splits three ways. *Look* has the Glass or Minimal style, whether items sit in a list or stack like a deck, the shelf's size, and the small stuff — names, shadow, edge tab. *Behavior* covers when the shelf shows up, how you move a floating one, and whether it stays out once it's empty. *Docking* chooses which edges it can use and whether it snaps in beside the Dock; snapping to an enabled edge is automatic, and at least one edge always stays enabled.

Perch remembers these choices between launches. Updates come through Sparkle, and since there's no Dock icon to notice a new version behind, a release worth mentioning says what changed once, on the launch after it installs, and then leaves you alone.

## Your files stay yours

Items on the shelf are stored as ordinary files under `~/Library/Application Support/Perch/` — or left exactly where you found them, if you told Perch to keep dropped files in place. There are no accounts or remote analytics. Perch only uses the network for automatic or manual update checks.

## Smart Perch

Smart Perch reads screenshots and PDFs you drop so it can give them useful names. It also remembers where you tend to put things and can offer that folder next time.

It is built into Perch but remains hidden and completely off until you deliberately enable it—no Smart database, text recognition, or learning runs in the background. Everything it learns stays in a file on your Mac and never leaves it. Removing Smart Perch deletes that learned data without affecting shelf items.

## License

[MIT](LICENSE) © Maximilian Reich

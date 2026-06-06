# Perch — Implementation Plan (task graph)

Milestone-ordered. **Every task must compile (`swift build`) and be independently
verifiable.** Each task lists: goal, exact files, the public interface it must expose
(already pinned as stubs in `Sources/Perch/`), acceptance criteria, and dependency ids.

> The stub skeleton already declares every public type and signature below. Implementing
> a task means replacing `fatalError("unimplemented")` / `TODO` bodies — **never** changing
> a pinned signature.

Legend: `Deps:` = task ids that must be done first.

---

## Milestone 0 — Scaffold

### T0.1 — Package + entry + empty panel
- **Goal:** launch an `.accessory` app that shows an empty `ShelfPanel`.
- **Files:** `Package.swift`, `Sources/Perch/main.swift`, `App/AppDelegate.swift`,
  `App/ShelfController.swift`, `Windows/ShelfPanel.swift`.
- **Public interface:**
  - `final class AppDelegate: NSObject, NSApplicationDelegate` with
    `func applicationDidFinishLaunching(_ notification: Notification)`.
  - `ShelfPanel.init(contentRect: NSRect)` configuring `.nonactivatingPanel`, window
    `level = .floating` (NOT `.statusBar`/`.mainMenu+` — those sit above the menu bar),
    `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`;
    `override var canBecomeKey: Bool { false }`.
  - `ShelfController.init() throws`, `func start()`.
- **Acceptance:** `swift build` clean; `swift run` shows a floating, non-activating panel
  that appears on all Spaces and does not take key focus; a full-height right-edge frame
  does **not** occlude the menu bar / notch (panel sits below the menu bar at `.floating`).
- **Deps:** none.

---

## Milestone 1 — Core round-trip (manual panel; drop in, drag out; NO auto-appear, NO promise polish)

### T1 — Data model + holding directory + persistence
- **Goal:** in-memory ordered store backed by the on-disk layout; `meta.json` /
  `index.json` round-trip.
- **Files:** `Model/StoredItem.swift`, `Model/ItemStore.swift`,
  `Storage/HoldingDirectory.swift`.
- **Public interface:**
  - `struct RepRecord: Codable, Equatable { let typeIdentifier: String; let fileName: String; let isPromisePlaceholder: Bool }`
  - `struct ItemMetadata: Codable, Equatable { let id: UUID; let createdAt: Date; var title: String; var representations: [RepRecord]; var backingFileNames: [String]; var primaryFileType: String? }`
  - `final class StoredItem: Identifiable { init(metadata:directoryURL:); var id: UUID; func data(forType:) -> Data?; func backingFileURLs() -> [URL]; func iconImage() -> NSImage }`
  - `final class ItemStore: ObservableObject { @Published private(set) var items: [StoredItem]; init(holding:); func load() throws; func insert(_:at:); func remove(_:); func newItemDirectory() -> (id: UUID, url: URL) }`
  - `struct HoldingDirectory { let root: URL; static func standard() throws -> HoldingDirectory; var itemsDir: URL; var indexFile: URL; func itemDir(_:) -> URL }`
- **Acceptance:** a debug path creates `~/Library/Application Support/Perch/items/<uuid>/{reps,files}` + `meta.json`, then `load()` on a fresh `ItemStore` returns the same items in `index.json` order.
- **Deps:** T0.1.

### T2 — Snapshot (data + real files only)
- **Goal:** snapshot all pasteboard representations and copy real files; promise types are
  recorded but not yet materialized.
- **Files:** `Storage/PasteboardSnapshotter.swift`.
- **Public interface:**
  - `struct PasteboardSnapshotter { let holding: HoldingDirectory; func snapshot(_ pasteboard: NSPasteboard, into store: ItemStore) throws -> (item: StoredItem, pendingPromises: [NSFilePromiseReceiver]) }`
- **Behavior:** for each `NSPasteboardItem`, write every `data(forType:)` to `rep-N.dat`;
  copy `public.file-url` targets into `files/`; record promise-only types with
  `isPromisePlaceholder = true`; write `meta.json`.
- **Acceptance (independently verifiable, no UI):** build a **synthetic** `NSPasteboard`
  (e.g. `NSPasteboard(name: .init("perch.test"))`, clear it, and `setData`/`setString` a
  couple of representations plus a `public.file-url` pointing at a temp file), call
  `snapshot(_:into:)`, and assert the correct on-disk layout: non-empty `rep-N.dat` per
  representation, the referenced file copied into `files/`, and a well-formed `meta.json`.
  (Real Finder-drag receipt is exercised later in T3 once the drop target exists.)
- **Deps:** T1.

### T3 — Receive view wired into the panel
- **Goal:** the panel accepts drops and routes them to the snapshotter→store.
- **Files:** `Receive/ShelfDropView.swift`; edits to `ShelfController`, `AppDelegate`.
- **Public interface:**
  - `protocol ShelfDropHandling: AnyObject { func handleDrop(_ pasteboard: NSPasteboard) -> Bool }`
  - `final class ShelfDropView: NSView { weak var dropHandler: ShelfDropHandling?; static let acceptedTypes: [NSPasteboard.PasteboardType]; override func draggingEntered(_:) -> NSDragOperation; override func performDragOperation(_:) -> Bool }`
  - `ShelfController: ShelfDropHandling`.
- **Acceptance:** dragging a file or text from another app onto the panel increments the
  store count (verify via log / count).
- **Deps:** T2.

### T4 — SwiftUI item list hosted in the panel
- **Goal:** live list of items (icon + title) inside the panel via `NSHostingView`.
- **Files:** `UI/ShelfContentView.swift`, `UI/ItemRowView.swift`; edit `ShelfController`.
- **Public interface:**
  - `struct ShelfContentView: View { @ObservedObject var store: ItemStore }`
  - `struct ItemRowView: View { let item: StoredItem }`
- **Acceptance:** dropped items appear as rows immediately; removing an item updates the UI.
- **Deps:** T3.

### T5 — Re-vend (basic: file URL + concrete data; `.copy`-only; AppKit-initiated; no lazy/promise yet)
- **Goal:** drag a row out via the AppKit host view, backed by the holding-dir file URL +
  stored data, with the drag source pinned to `.copy` so the master is never moved.
- **Files:** `Vend/ItemDragSource.swift`, `UI/ShelfHostView.swift`.
- **Public interface (re-pinned — Decisions K, L, M):**
  - `final class ItemDragSource: NSObject, NSDraggingSource { init(item: StoredItem); func beginDrag(from view: NSView, event: NSEvent) -> NSDraggingSession; func draggingItem() -> NSDraggingItem; func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation }`
    — `draggingSession(_:sourceOperationMaskFor:)` returns **`.copy`** for file-backed items
    in **both** `.withinApplication` and `.outsideApplication` contexts.
  - `final class ShelfHostView: NSView { init(store: ItemStore); required init?(coder: NSCoder); override func mouseDragged(with event: NSEvent) }`
    — hosts `ShelfContentView` via `NSHostingView`; `mouseDragged(_:)` is the **primary**
    drag-initiation path: it identifies the hit row, creates an `ItemDragSource`, **retains
    it for the drag duration**, and calls `beginDrag(from:event:)`. (SwiftUI gesture is off
    the critical path; the prior `ItemRowDragModifier` is removed.)
- **Acceptance:** drag a row to the Desktop → file is copied out **and the master under
  `files/` still exists** (drag must be copy, never move); drag a text item into TextEdit →
  the text appears. Drag is initiated by AppKit `mouseDragged`, not a SwiftUI gesture.
- **Deps:** T4.

> **M1 GATE:** Finder file → panel row → Desktop copy; and TextEdit selection → panel →
> TextEdit, with no promises and no edge strip.

---

## Milestone 2 — File promises (RECEIVE direction)

### T6 — File promise materializer
- **Goal:** drive `NSFilePromiseReceiver`s into an item's `files/`.
- **Files:** `Storage/FilePromiseMaterializer.swift`.
- **Public interface:**
  - `final class FilePromiseMaterializer { let operationQueue: OperationQueue; init(); func materialize(_ receivers: [NSFilePromiseReceiver], into filesDir: URL, completion: @escaping ([URL]) -> Void) }`
- **Acceptance:** a standalone call materializes a promise receiver's files into a target dir.
- **Deps:** T5.

### T7 — Wire promise receipt into snapshot/store
- **Goal:** promises dragged in produce real files + a row.
- **Files:** edits to `PasteboardSnapshotter.swift`, `ShelfDropView.swift`,
  `ShelfController.swift`.
- **Acceptance:** dragging an image from **Photos** (promise-only source) onto the panel
  yields a real file in `files/` and a row. **`FilePromiseMaterializer`'s completion fires
  on its `OperationQueue` (off-main); the wiring MUST hop to the main actor (e.g.
  `Task { @MainActor in … }` / `DispatchQueue.main`) before mutating `ItemStore`** (it is
  `@MainActor` + `@Published`). Verify the resulting `@Published` mutation occurs on the
  main thread (assert `Thread.isMainThread` at the store mutation, or via the Main Thread
  Checker).
- **Deps:** T6.

---

## Milestone 3 — File promises (RE-VEND direction) + lazy data

### T8 — Promise + lazy writer
- **Goal:** an `NSFilePromiseProvider` subclass that also offers the item's generic types
  lazily.
- **Files:** `Vend/StoredItemDragWriter.swift` (provider + delegate).
- **Public interface:**
  - `final class StoredItemDragWriter: NSFilePromiseProvider { init(item: StoredItem); override func writableTypes(for:) -> [NSPasteboard.PasteboardType]; override func writingOptions(forType:pasteboard:) -> NSPasteboard.WritingOptions; override func pasteboardPropertyList(forType:) -> Any? }`
  - `final class StoredItemDragWriterDelegate: NSObject, NSFilePromiseProviderDelegate { init(item: StoredItem); filePromiseProvider(_:fileNameForType:); filePromiseProvider(_:writePromiseTo:completionHandler:); operationQueue(for:) }`
- **Acceptance:** the writer reports correct `writableTypes` and writes the promised file
  on demand from the holding dir.
- **Deps:** T7.

### T9 — Single-item multi-representation drag (promise-preferred, copy-only)
- **Goal:** use `StoredItemDragWriter` as the writer for the drag-out (Decisions F, K),
  with **file delivery promise-preferred** and the concrete file URL kept only as an
  instant-local convenience.
- **Files:** edit `Vend/ItemDragSource.swift`.
- **Acceptance:** drag a row into a promise-only destination (e.g. Mail compose) → the file
  materializes via the promise (a fresh copy, master untouched); local drops remain instant
  via the convenience file URL; generic data still flows. **After every drag-out, the master
  under `files/` still exists** (promise-preferred + `.copy`-only guarantee the holding-dir
  master is never exposed or moved).
- **Deps:** T8.

> **M3 GATE:** Promises work in **both** directions (Photos-in, Mail-out).

---

## Milestone 4 — Edge-strip auto-appear

### T10 — Edge strip window
- **Goal:** a thin, transparent, full-height right-edge panel registered for dragged types
  that fires a delegate on `draggingEntered`.
- **Files:** `Windows/EdgeStripWindow.swift`.
- **Public interface (re-pinned — Decision G):**
  - `protocol EdgeStripDelegate: AnyObject { func edgeStripDidReceiveDrag(_ strip: EdgeStripWindow) }`
  - `final class EdgeStripWindow: NSPanel { static let stripWidth: CGFloat /* = 4 */; weak var stripDelegate: EdgeStripDelegate?; init(screen: NSScreen) }`
- **Geometry / event policy (pinned):** width = `stripWidth` (4 pt), full screen height,
  pinned to the right edge; `ignoresMouseEvents = false` (**required** to receive
  `draggingEntered`). **Documented tradeoff:** because it is not click-through, the strip
  also captures idle clicks within that ~4 pt edge region — accepted, minimized by the thin
  width. (See RISKS item 7 for the conditional click-through alternative.)
- **Acceptance:** dragging anything to the right edge fires the delegate (verify via log);
  the strip is ≤ `stripWidth` pt wide and full-height.
- **Deps:** T5 (needs a working panel; independent of M2/M3).

### T11 — Reveal/hide controller
- **Goal:** the strip reveals the panel (slide in from the edge); auto-hide after
  drop/timeout; persist frame.
- **Files:** `Windows/ShelfWindowController.swift`; edit `ShelfController.swift`.
- **Public interface:**
  - `final class ShelfWindowController { let panel: ShelfPanel; init(panel:); func reveal(animated:); func hide(animated:); func restorePersistedFrame(); func persistFrame() }`
  - `ShelfController: EdgeStripDelegate`.
- **Acceptance:** drag to edge → shelf slides in → drop lands → shelf hides.
- **Deps:** T10.

---

## Milestone 5 — Polish / optional

### T12 — Item delete + clear-all + Quick Look
- **Goal:** affordances to remove items and preview them, driven through **AppKit** on the
  host view (Decision M) — not via SwiftUI controls, which a never-key panel does not
  reliably deliver.
- **Files:** edits to `UI/ShelfHostView.swift` (AppKit controls: context menu / key
  handling for delete + clear-all, Quick Look via `QLPreviewPanel`), `Model/ItemStore.swift`
  (`remove`, plus a `clearAll()`); `UI/ItemRowView.swift` for purely visual affordances.
- **Acceptance:** right-click / key-driven delete on the host view removes a row, deletes its
  `items/<uuid>/` dir, and updates the UI; clear-all empties the shelf; Quick Look opens a
  preview. The delete/clear interactions work while the panel is non-key (AppKit path), with
  no reliance on SwiftUI gesture/button delivery.
- **Deps:** T4, T5 (`ShelfHostView`).

### T13 — (Optional, permission-sensitive) global mouse monitor pre-warm
- **Goal:** a global `NSEvent` mouse monitor to pre-warm/expand the strip; gated behind a
  flag. **See `RISKS.md` item 1 before implementing.**
- **Files:** new `App/MouseMonitor.swift` (no signature pinned yet — additive, optional).
- **Acceptance:** with the flag on, the monitor fires on global mouse-drag without a TCC
  prompt; with the flag off, behavior is unchanged.
- **Deps:** T11.

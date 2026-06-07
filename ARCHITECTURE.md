# Perch — Architecture

## 1. Conceptual model: temporal decoupling of source and destination

In ordinary macOS drag-and-drop, a single drag connects one **source** and one
**destination** that are alive at the *same instant*. The dragging pasteboard exists only
for the duration of that one gesture; once the drop completes (or is cancelled), the
source's representations and any file promises are gone.

Perch inserts itself as a **persistent intermediary** that breaks this temporal coupling:

```
   SOURCE app                 PERCH (the shelf)                 DEST app
   (alive at t0)              (alive across t0..t1)             (alive at t1)

   drag ──► RECEIVE ──► STORE (snapshot everything to disk) ─┐
                                                              │   (time passes,
                                                              │    source may quit)
                                                              └─► RE-VEND ──► drag ──►
```

Because the source pasteboard is ephemeral, Perch must **fully capture** every
representation at receive time (t0) — it cannot lazily reach back to the source later. It
then **faithfully re-offers** those representations at vend time (t1), using file promises
and lazy data providers so large payloads are only reconstituted when an eventual
destination actually asks for them. The destination at t1 need not be the source from t0,
and the source need not still be running.

## 2. The three pipelines

### RECEIVE (`NSDraggingDestination`)
The shelf's drop view (`ShelfDropView`) and the edge strip (`EdgeStripWindow`) register
for dragged types. `draggingEntered(_:)` validates and (for the strip) triggers reveal;
`performDragOperation(_:)` hands the incoming `NSDraggingInfo`'s pasteboard to STORE.

### STORE
Three responsibilities, all at receive time:
1. **Copy real files** referenced by `public.file-url` into the item's `files/` directory
   (so the shelf owns a stable copy even if the original moves/deletes).
2. **Snapshot ALL pasteboard representations** — for every `NSPasteboardItem`, for every
   declared type, persist `data(forType:)` to `reps/rep-N.dat` and record the
   type→file mapping in `meta.json`.
3. **Materialize file promises** dragged in (e.g. from Photos/Mail) via
   `NSFilePromiseReceiver`, writing the promised files into `files/`.

### RE-VEND
On drag-out, an `ItemDragSource` — a concrete **`NSDraggingSource`** object retained by
the host view — calls `beginDraggingSession(with:event:source:)` with a single
`NSDraggingItem` backed by a `StoredItemDragWriter` (an `NSFilePromiseProvider` subclass).
The writer offers, **in priority order for file delivery**:
- the **`NSFilePromiseProvider` promise** as the *primary* file path — it always writes a
  **fresh copy** into the destination and **never exposes the holding-dir master**;
- a concrete **file URL** into the holding dir only as an *instant-local convenience*
  (e.g. same-app/local drops), never as a moveable handle to the master;
- the item's stored **generic representations** lazily via overridden
  `pasteboardPropertyList(forType:)` (text/RTF/image/URL/etc., reconstructed from
  `reps/` on demand — the lazy `NSPasteboardItemDataProvider` role).

The master file under `files/` must survive every drag-out. `ItemDragSource` enforces this
by implementing `draggingSession(_:sourceOperationMaskFor:)` to return **`.copy`** for
file-backed items in **both** drag contexts, so no destination (Finder included) can move
or relocate the master out of the shelf.

## 3. Module / component map

| Layer | Type | Responsibility |
|-------|------|----------------|
| App | `main.swift` | Build `NSApplication`, set `.accessory`, run. |
| App | `AppDelegate` | `NSApplicationDelegate`; owns the `ShelfController`. |
| App | `ShelfController` | `@MainActor` coordinator wiring store + windows + pipelines; conforms to `ShelfDropHandling` and `EdgeStripDelegate`. |
| Model | `StoredItem`, `ItemMetadata`, `RepRecord` | One stored item + its on-disk metadata. |
| Model | `ItemStore` | `ObservableObject` in-memory ordered list + persistence facade. |
| Storage | `HoldingDirectory` | Application Support paths and on-disk layout. |
| Storage | `PasteboardSnapshotter` | RECEIVE→STORE: snapshot all reps + copy files. |
| Storage | `FilePromiseMaterializer` | STORE: drive `NSFilePromiseReceiver`s into `files/`. |
| Receive | `ShelfDropView` | `NSView` + `NSDraggingDestination` inside the panel. |
| Vend | `StoredItemDragWriter` (+ delegate) | RE-VEND: promise-preferred file delivery + lazy generic data + convenience file URL, in one object. |
| Vend | `ItemDragSource` | Concrete **`NSDraggingSource`** class (retained by the host view): builds the `NSDraggingItem`, starts the session, and pins the operation mask to `.copy` for file items. |
| Windows | `ShelfPanel` | `NSPanel` shelf (non-activating, `.floating` level — below the menu bar, all-spaces). |
| Windows | `EdgeStripWindow` | Thin (`stripWidth` pt) right-edge window registered for dragged types; `ignoresMouseEvents = false`. |
| Windows | `ShelfWindowController` | Reveal/hide/animate the panel; persist frame. |
| UI | `ShelfContentView`, `ItemRowView` | SwiftUI item views hosted via `NSHostingView`. |
| UI | `ShelfHostView` | AppKit host (`NSView`) for the SwiftUI content: **primary** path for row drag-initiation (`mouseDragged(_:)` → owns/retains an `ItemDragSource`) and interactive controls (delete/clear). SwiftUI gestures are off the critical path. |

SwiftUI is used **only** for individual item rendering inside `NSHostingView`; all window,
panel, and drag/drop control is AppKit.

## 4. Data model for a stored item

### In-memory
- `StoredItem` — holds `ItemMetadata` + the item's `directoryURL`; reads representation
  data and backing files lazily from disk.
- `ItemMetadata` (`Codable`): `id: UUID`, `createdAt: Date`, `title: String`,
  `representations: [RepRecord]`, `backingFileNames: [String]`, `primaryFileType: String?`.
- `RepRecord` (`Codable`): `typeIdentifier: String` (the `NSPasteboard.PasteboardType`
  raw value), `fileName: String` (`"rep-N.dat"`), `isPromisePlaceholder: Bool`.

### On disk
```
~/Library/Application Support/Perch/
  index.json                      # ordered [item UUID] — display order
  items/
    <item-uuid>/
      meta.json                   # ItemMetadata (Codable, JSON)
      reps/
        rep-0.dat                 # raw pasteboard data, one file per representation
        rep-1.dat
        ...
      files/
        <original filename>       # copied real files + materialized promise outputs
```

Representations are stored as opaque `rep-<index>.dat` blobs with the type identifier
recorded in `meta.json`, so arbitrary (and filesystem-unsafe) pasteboard type strings
never need to appear in a filename. `index.json` is the single source of truth for
display order; `backingFileNames` lists the real files in `files/` that the item can vend
by file URL / promise.

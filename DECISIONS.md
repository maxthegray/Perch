# Perch — Decisions

Every decision below is **fixed**. Implementers must treat these as constraints and must
not relitigate them. Each has a one-line rationale.

## Locked by the original brief

| # | Decision | Rationale |
|---|----------|-----------|
| L1 | **Swift + AppKit**; SwiftUI only via `NSHostingView` for individual item views. | AppKit is required for non-activating panels, window levels, and full drag/drop control; SwiftUI is convenient only for item rendering. |
| L2 | The shelf is an **`NSPanel`** with `.nonactivatingPanel`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`, and window **`level = .floating`** (NOT `.statusBar`/`.mainMenu+`, which sit above the menu bar). | A shelf must float above ordinary app windows, appear on every Space, and never steal key focus — while still staying *below* the menu bar so a full-height right-edge panel cannot occlude the menu bar / notch. |
| L3 | **Primary appear-mechanism = a persistent transparent edge-strip window** registered for dragged types; `draggingEntered(_:)` expands it into the shelf. | Reliable, permission-free trigger that works the instant a drag touches the edge. |
| L4 | A **global mouse monitor + drag-pasteboard inspection is OPTIONAL** later enhancement, not core. | Avoids any permission/version risk on the critical path. |
| L5 | **Three pipelines**: RECEIVE (`NSDraggingDestination`), STORE (copy files into the holding dir; snapshot ALL pasteboard representations per item; materialize promises via `NSFilePromiseReceiver`), RE-VEND (`beginDraggingSession`, back files with both a file URL and an `NSFilePromiseProvider`, lazy `NSPasteboardItemDataProvider` for generic data). | Clean separation of the temporal-decoupling responsibilities. |
| L6 | **File promises in BOTH directions are mandatory.** | Many real sources/destinations (Photos, Mail, Messages) only speak promises; without them the shelf silently loses data. |
| L7 | **Personal use: unsandboxed, self-signed.** No App Store / sandbox constraints. | Enables real Application Support paths and arbitrary file copies. |

## Added during planning

| # | Decision | Rationale |
|---|----------|-----------|
| A | SwiftPM **executable** target, run via `swift run`; `NSApp.setActivationPolicy(.accessory)` at launch. | `swift build` is a trivial per-task verification gate; no `.app`/Info.plist bundling needed for personal use. |
| B | Swift **language mode 5** (`swiftLanguageModes: [.v5]`); AppKit-touching types marked `@MainActor`. | Avoids Swift 6 strict-concurrency churn derailing the implementer. |
| C | Minimum platform **`.macOS(.v14)`**. | A floor below the dev machine (macOS 26) so no version-gated enum cases are required; all APIs used exist on ≥ 12. |
| D | On-disk representations stored as **`rep-<index>.dat`**; the type→file mapping lives in `meta.json`. | Sidesteps filesystem-unsafe pasteboard type strings (spaces, slashes, `dyn.` UTIs) entirely. |
| E | Persistence = **JSON via `Codable`** — `meta.json` per item, `index.json` for order. | Human-inspectable, zero dependencies, trivial to evolve. |
| F | Re-vend uses **one** `NSDraggingItem` whose writer is a `StoredItemDragWriter: NSFilePromiseProvider` subclass that *adds* the item's stored generic types (lazy) on top of the file delivery. **File delivery is promise-preferred:** the `NSFilePromiseProvider` promise is the primary file path (it always writes a *fresh copy*, never exposing the holding-dir master); a concrete holding-dir file URL is offered only as an instant-local convenience. The drag is **`.copy`-only** (see Decision K) so neither path can move the master. | One coherent object is promise provider + lazy generic-data provider; promise-first + copy-only guarantees the holding-dir master is never moved or relocated out of the shelf. |
| K | RE-VEND drags are **`.copy`-only**: the drag source conforms to `NSDraggingSource` and returns `.copy` from `draggingSession(_:sourceOperationMaskFor:)` for file-backed items, for **both** `.withinApplication` and `.outsideApplication` contexts. | A destination (Finder included) must never be able to move/relocate the holding-dir master file out of the shelf. |
| L | The RE-VEND drag source is a **concrete `NSDraggingSource` class** (`ItemDragSource`), retained by the host view for the drag's duration — NOT a struct with a static method (a struct cannot serve as the `source:` argument to `beginDraggingSession(with:event:source:)`, and `NSView` does not conform to `NSDraggingSource` by default). | The `.copy` operation mask (Decision K) must live on a real `NSDraggingSource` object. |
| M | AppKit is the **primary** path for both row drag-initiation (`mouseDragged(_:)` on an AppKit host view) and interactive controls (delete/clear). SwiftUI gestures are **off the critical path** (not sequenced as a "try SwiftUI first, fall back to AppKit"). | A `.nonactivatingPanel` that never becomes key does not reliably deliver SwiftUI gestures/interaction; AppKit event handling on the host view is the dependable path. |
| G | The edge strip **never accepts the drop**; `draggingEntered` only reveals the panel, then the panel's own `ShelfDropView` is the real destination. **Geometry/event policy:** the strip is a thin (`EdgeStripWindow.stripWidth = 4` pt) full-height window pinned to the right edge with `ignoresMouseEvents = false` (required to receive `draggingEntered`); the accepted tradeoff is that the strip also captures idle clicks in that ~4 pt edge region. | Clean separation: strip = trigger, panel = receiver. A non-click-through strip is needed for drag receipt; keeping it a few px wide minimizes the idle-click-capture cost. |
| H | Holding directory = **`~/Library/Application Support/Perch/`** (real, unsandboxed path). | Locked use case; stable across runs. |
| I | App lifecycle via a classic **`@main`-style top-level `main.swift` + `AppDelegate`**, not the SwiftUI `App` lifecycle. | Full control over panel/window levels and non-activating behavior. |
| J | App/product name = **Perch**; repo at `Coding/Swift/Perch`. | Confirmed with the user during planning. |

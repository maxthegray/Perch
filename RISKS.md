# Perch — Risks (version- and permission-sensitive; flagged for human verification)

## Measured environment (this machine)

| Tool | Version |
|------|---------|
| Xcode | **26.5** (build 17F42) |
| macOS | **26.5.1** (build 25F80) |
| macOS SDK | **26.5** (`macosx26.5`) |
| Swift | **6.3.2** (swiftlang-6.3.2.1.108), target `arm64-apple-macosx26` |

Source commands: `xcodebuild -version`, `sw_vers`, `xcodebuild -showsdks`,
`swift --version`. Findings below are reported from documented behavior + measured
versions; items marked **VERIFY** require a human runtime check — they are not asserted as
confirmed.

---

## 1. Global mouse monitor & permissions (the brief's specific question)

**Question:** do global `NSEvent` mouse monitors require any permission on the macOS
version on this machine (26.5.1)?

**Finding (documented behavior, not yet runtime-verified on 26.5.1):**
`NSEvent.addGlobalMonitorForEvents(matching:handler:)` observing **mouse** event masks
(e.g. `.leftMouseDragged`, `.mouseMoved`, `.leftMouseDown/Up`) is documented to require
**no** special permission. Per Apple's documentation, the restriction applies only to
**key-related** events: *"key-related events may only be monitored if accessibility is
enabled or if your application is trusted for accessibility access"*
(`AXIsProcessTrusted`). Perch's optional T13 monitor watches **mouse events only**, so it
is expected to need **no** Accessibility/TCC grant.

**VERIFY (human, before relying on T13):** add the mouse-only global monitor, run via
`swift run`, and confirm (a) no TCC/Accessibility prompt appears and (b) the handler fires
while dragging over other apps. If a prompt appears, the assumption is wrong for this OS
build and T13 must gate behind an Accessibility request. This uncertainty is exactly why
the monitor is **optional / non-core** (Decisions L4).

> Note: global monitors never see events targeted at Perch's own windows, and cannot
> consume/modify events — both fine for a pre-warm trigger. The edge-strip (`draggingEntered`)
> mechanism, which needs no monitor at all, remains the primary appear path.

## 2. TCC grant stability under unbundled `swift run` (Decision A)

We run an unbundled binary out of `.build/` (no `.app`). Any TCC grant a feature might
later require (Accessibility for T13 if assumption 1 fails; Screen Recording / Quick Look
thumbnailing; Full Disk Access for certain locations) binds to **that binary path** and
may **reset on rebuild** as the path/signature changes. **VERIFY / mitigation:** if any
persistent permission becomes necessary, switch to a stable, self-signed `.app` bundle
with a fixed bundle identifier so the grant survives rebuilds.

## 3. Swift 6.3 strict concurrency

The toolchain is Swift 6.3.2. Mitigated by Decision B (`swiftLanguageModes: [.v5]` +
explicit `@MainActor` on AppKit-touching types).

**REQUIREMENT (not merely a note):** promise completion runs **off the main actor**.
`FilePromiseMaterializer`'s completion fires on its `OperationQueue`, and the
`NSFilePromiseProviderDelegate` writes happen on a background `operationQueue`. Any code
path that mutates `ItemStore` (which is `@MainActor` + `@Published`) from those callbacks
**must hop to the main actor first** (e.g. `Task { @MainActor in … }` or
`DispatchQueue.main.async`). This is an explicit acceptance criterion of T7 — an off-main
`@Published` publish is a defect, not a warning to defer.

**VERIFY:** if a future dependency or setting forces language mode 6, AppKit main-actor
isolation across the drag/drop callbacks and the background promise queues must be
re-audited.

## 4. `NSFilePromiseProvider` subclassing to add generic types (Decision F)

Subclassing `NSFilePromiseProvider` and extending `writableTypes(for:)` /
`pasteboardPropertyList(forType:)` to also vend non-file representations is a known but
finicky pattern; ordering and `writingOptions` (e.g. `.promised`) affect which destinations
pick the promise vs. the concrete data. **VERIFY:** test against real promise-only
destinations (Mail compose, Messages) **and** plain-data destinations (TextEdit, Finder)
on macOS 26 to confirm each picks the intended representation.

## 5. Non-activating panel breaks SwiftUI interaction (drag-out AND controls)

A `.nonactivatingPanel` that returns `canBecomeKey = false` hosting SwiftUI via
`NSHostingView` may not reliably receive mouse/keyboard interaction — this affects **both**
row drag-initiation **and** interactive controls (T12 delete / clear-all / Quick Look), not
just drag-out. **Decision M therefore makes AppKit the primary path for both:** drag-out is
initiated from `ShelfHostView.mouseDragged(_:)`, and delete/clear are AppKit affordances
(context menu / key handling) on the host view — SwiftUI gestures/buttons are off the
critical path (the `ItemRowDragModifier` SwiftUI bridge is removed). **VERIFY:** confirm (a)
row drag-out initiates from the AppKit host while the panel stays non-key and does not steal
focus from the source/destination app, and (b) T12's delete/clear/Quick Look interactions
fire while the panel is non-key.

## 6. Window level: float-over vs. menu-bar over-occlusion (both directions)

The panel must float over ordinary windows **without** occluding the menu bar / notch.
Decision L2 pins `level = .floating` (NOT `.statusBar`/`.mainMenu+`, which sit *above* the
menu bar and would let a full-height right-edge panel cover the menu bar / notch).
**VERIFY both directions:** (a) **under-float** — the shelf still appears over normal app
windows and over a full-screen app's Space (`.fullScreenAuxiliary` + `.canJoinAllSpaces`);
and (b) **over-occlusion** — a full-height right-edge panel at `.floating` does **not** cover
the menu bar / notch region on this display. If `.floating` proves too low for the
full-screen case, prefer **insetting the panel below the menu bar** over raising the level
above it.

## 7. Does macOS route drags to an `ignoresMouseEvents = true` window? (edge strip)

The edge strip needs `draggingEntered` (Decision G / T10), so it is pinned to
`ignoresMouseEvents = false`, which means it also captures idle clicks in its ~4 pt region.
**VERIFY on this macOS build:** whether a registered-for-dragged-types window with
`ignoresMouseEvents = true` still receives `draggingEntered`. If it **does**, the strip can
be made click-through (`ignoresMouseEvents = true`) and keep drag receipt — eliminating the
idle-click capture. If it **does not**, the thin-strip (`stripWidth = 4`) + non-click-through
mitigation stands as the accepted tradeoff.

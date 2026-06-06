# Perch

A personal, unsandboxed, self-signed Yoink-style drag-and-drop **shelf** for macOS.
Drag anything onto the screen-edge strip, Perch holds it, and you drag it back out later —
into any destination app, with file promises in both directions.

This repository currently contains the **design docs + a compiling stub skeleton**. No
pipeline logic is implemented yet; bodies are `fatalError("unimplemented")` / `TODO`.

## Run

```sh
swift build      # compiles the stub skeleton
swift run        # launches the (currently empty) .accessory app
```

The app runs as an accessory (no Dock icon, no menu bar) via
`NSApp.setActivationPolicy(.accessory)`.

## Docs

- [`ARCHITECTURE.md`](ARCHITECTURE.md) — conceptual model, pipelines, component map, data model.
- [`DECISIONS.md`](DECISIONS.md) — every locked architectural decision + rationale.
- [`PLAN.md`](PLAN.md) — the task graph to implement, milestone-ordered.
- [`RISKS.md`](RISKS.md) — version/permission-sensitive items flagged for human verification.

Implementers (e.g. Codex) execute `PLAN.md` task-by-task; all architectural decisions are
fixed in `DECISIONS.md` and physically pinned by the public type signatures in
`Sources/Perch/`.

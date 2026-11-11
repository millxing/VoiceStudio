# Multiple Selection Implementation Plan

**Goal:** Apply script, source clip, and timeline editing actions to the full selection.

**Architecture:** Keep native SwiftUI List selection sets for scripts and source clips. Store a set of timeline clip IDs and route native editing commands through it. Preserve single-item accessors for preview and existing callers.

**Tech Stack:** Swift 6, SwiftUI, AppKit, existing background self-test.

- [x] Update `Models.swift`, `ContentView.swift`, `TakesView.swift`, `EditorView.swift`, and `App.swift`: selection-aware context menus, list Delete handlers, batch source removal with undo, and batch placement on a track.
- [x] Update `EditorModel.swift`, `TimelineKeyboard.swift`, and `EditorView.swift`: additive Shift-click and Command-click, selected highlighting, batch delete/ripple/split, array clipboard with legacy decoding, and group movement.
- [x] Extend `SelfTest.swift`: multiple selection, batch clipboard spacing, cut/delete/undo, and source removal/placement checks using temporary data.
- [x] Run `VOICE_TEST_REFERENCE=../results/mps-reference-1.wav ./build.sh`, `tools/check.sh`, `tools/selftest.sh`, and `tools/integration.sh`.
- [x] Capture `APP_SNAPSHOT_PAGES=scripts,takes,editor tools/snap.sh`, inspect light/dark images, run `tools/grid-lint.sh` and `swift tools/check-layout.swift /tmp/VoiceStudio-shots/*-layout.json`.
- [x] Review diff and commit the verified change.

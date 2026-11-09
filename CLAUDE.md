# VoiceStudio

A native macOS app in SwiftUI. It runs on this Mac only, with a local
Codable JSON library and no server.

## Layout

- `Sources/VoiceStudio/` the app. `App.swift` has the window, menus, and the database location.
- `Sources/VoiceStudioKit/` rules and data logic with no SwiftUI. Tests in `Tests/VoiceStudioKitTests/`.
- `Package.swift` a Swift package. There is no Xcode project.
- `build.sh` builds, signs, and installs `/Applications/VoiceStudio.app`. The user requires the systemwide `/Applications` folder for all future builds; keep build, launch, and verification scripts aligned with it.
- `Icon/AppIcon.icon` the app icon, an Icon Composer file (JSON plus SVG layers). `build.sh` compiles it with `tools/make_icon.sh`; `tools/icon_review.sh` renders every look into one PNG.
- `docs/` the brief, the screen index, and the user stories, when they exist.

## Build and check

- Build and install: `./build.sh`. Add `--open` to restart the app with the new build. The build shows warnings; fix them.
- Library and worker checks: `tools/check.sh`. This CLT lacks the Swift Testing/XCTest runtime.
- Self-test (the app's real functions on a /tmp store): `tools/selftest.sh`. Build with `VOICE_TEST_REFERENCE=../results/mps-reference-1.wav ./build.sh` first; without a bundled reference the voice check fails. Exit 0 when every check passes. Add a check for every story with logic in `SelfTest.swift`.
- After every UI change, take snapshots with sample data and look at them: `tools/snap.sh`.
  It writes `/tmp/VoiceStudio-shots/<page>-light.png` and `-dark.png` for every sidebar page, and `settings-<tab>-light.png` and `-dark.png` for every Settings tab, then quits. `APP_SNAPSHOT_PAGES=all,settings tools/snap.sh` limits the pages.
  For a panel, sheet, or popover, add a capture to `Snapshot.swift` like the Settings loop.
- Snapshots, seed data, and the self-test refuse to run without `APP_STORE` in /tmp.
- Never test against the real database in `~/Library/Application Support/VoiceStudio/`.
- Then check the grid: `tools/grid-lint.sh` and `swift tools/check-layout.swift /tmp/VoiceStudio-shots/*-layout.json`. Both print PASS.
- A change is done when the build has no errors, the grid checks pass, and you looked at the light and dark snapshots.

## Design rules

- Use Apple's controls and system styles. Only the accent color is custom: `UI/Theme.swift` (`ThemeStore.defaultID`). People change it, and light or dark mode, in Settings > Appearance.
- Views use `.tint`, `Palette.accent`, `Palette.accentText` (accent-colored text), and `Palette.onAccent` (text on an accent fill). Never hard-code colors, radii, or durations in views.
- Compare accents: add `APP_ACCENT=<id>` to the snapshot command.
- Spacing comes from `Space` in `UI/Grid.swift`, on a 4 pt grid. Mark custom pages and cards with `.gridArea` and `.gridProbe`.
- Windows open calm: `.noInitialFocus()` on every window and sheet (no focus ring or selected text on open), `.fitsContent()` on sheets and Settings tabs (no scroll bar with nothing to scroll). System scroll bars. Both in `UI/WindowBehavior.swift`.
- Settings: one tab per topic in `SettingsView.swift`, one grouped Form per tab. Add a case to `SettingsTab` for a new tab.
- Window chrome (title bar, toolbar, sidebar, menus, sheets) stays system. Buttons use system styles, like `.borderedProminent`.
- Colors: `.primary`, `.secondary`, `.tint`, and system colors. Never fixed grays or white for text.
- Every action has a menu bar item and a keyboard shortcut.
- `Label` for icon and text pairs. SF Symbols for icons.
- `ContentUnavailableView` for empty states.
- Liquid Glass belongs to floating controls only, never to content.

## Skills

The bama plugin has a skill for each step: `mac-design` (design rules),
`design-system` (accent and tokens), `layout-grid`, `ux-design`,
`swift-swiftui`, `os-integrations`, `performance`, `build-and-verify`,
`test-mac-app`, `app-icon`, `user-stories`, and `improve-loop`. Use them.

## Git

- Commit after each working change, with a message that says what the user can now do.

## Current implementation and remaining manual checks

- Metadata is Codable JSON with atomic writes; source audio is separate in Application Support.
- Resources/worker.py is installed from Engine/worker.py by build.sh; the Python runtime remains external and configurable.
- Run tools/integration.sh after changing process callbacks, the generation queue, audio playback, or the worker protocol.
- Never run automated mutations against the real library. Use APP_STORE=/tmp/<name>.store.
- External menu audit still needed: with no script selection, Speech > Generate Selected is disabled; selecting scripts enables it. While running, Stop Queue is enabled. With no completed take selected, Playback commands are disabled. Selecting a completed take enables them. CUA attachment returned cgWindowNotFound on this machine; do not report hover checks as passed until actually observed.
- Editor: `library.timeline` (VoiceStudioKit/Timeline.swift) holds clips on 3 tracks; mixing is `TimelineMixer` (mono, 24 kHz). Drags edit a view-local draft and commit one undo step on release. macOS has no MP3 encoder, so MP3 export shells out to Homebrew `lame` or `ffmpeg`.
- Microphone/input-device and VoiceOver checks are still manual. See docs/VERIFICATION.md.

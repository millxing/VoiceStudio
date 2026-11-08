# Verification — 2026-11-08

Installed release: `/Applications/VoiceStudio.app` (ad hoc signed), macOS 26.6.2,
M4 Max / 64 GB. Swift 6 language mode. No Swift source warnings. The installed
CLT emits linker warnings about missing Xcode framework search paths; documented
in README. No system toolchain files were changed.

## Automated results

- `tools/check.sh`: 12 Foundation library checks passed, plus 2 Python chunking
  tests covering sentence boundaries, long unbroken input, CJK, emoji, empty
  input, and preservation of every non-whitespace character.
- `tools/selftest.sh`: 11 app-action checks passed. Multiple UTF-8/UTF-16 imports,
  reopening the library, removal/Undo, copying multiple voice references,
  two scripts × two takes, invalid Python recovery, and queue cancellation.
- `tools/integration.sh`: 17 checks passed on the installed release. Two scripts
  × two independent takes, a long multi-part script, reference-audio voice
  cloning on strict MPS, native playback advancing/pause/resume/seek, exact WAV
  export copy, retained metadata, model reuse, and stopping active generation.
  Integration references were synthetic benchmark audio, not a test of real
  speaker likeness. Logs: `verification/integration.log`.
- Custom-folder worker smoke test passed against the locally cached XTTS model
  folder. Invalid-request error was recoverable; subsequent French generation
  at 1.10× speed produced a valid WAV. No alternate fine-tuned checkpoint was
  available to test; custom checkpoint compatibility remains model-dependent.
- All 17 language tokenizers accepted representative native-language text,
  including Chinese, Japanese, Korean, Hindi, and Arabic. Speech generation was
  exercised in English and French; other languages have not had listening review.
- Static grid lint and every light/dark layout-probe file passed.
- Tests used `/tmp` stores and source copies, never the personal application-
  support library or the other macOS account's installation.

## Visual review

Images and layout files are saved in `screenshots/`.

- Scripts, light/dark: sidebar and editable list remain readable; the selected
  script has a large native text editor with generation controls below. Voice,
  language, and speed labels share an edge; controls fit at the supported size.
- Voices, light/dark: named reference library, speech guidance, preview transport,
  and Use This Voice/Edit Voice actions are visible and readable.
- Takes, light/dark: each alternate take has a status and duration. Detail shows
  playback, export/reveal/regenerate actions, immutable settings and source text.
- Add Voice, light/dark: compact named task sheet, import/record controls, clear
  empty reference state, Cancel, and disabled Save until valid. Background dimming
  is native sheet behavior.
- Engine settings, light/dark: native grouped form shows device/model/runtime,
  restart/log actions, autoplay, and the library location without clipping.
- Appearance settings, light/dark: accent preview uses studio-specific content
  and standard color swatches. No remaining task-manager placeholder labels.

## Manual checks still needed

- First-use microphone permission and recording with the user's chosen input.
  Import-based cloning and reference playback are verified.
- Actual speaker likeness and listening quality with the user's own recordings.
- Toolbar tooltips, menu state from an external accessibility client, keyboard-
  only traversal, and VoiceOver have not been verified. Computer-use attachment
  failed twice with `cgWindowNotFound`; the app's own active-window screenshots
  succeeded. Native controls have labels/help and commands, but source inspection
  does not replace the missing visible hover verification.
- Finder's reveal window and interactive save-panel behavior were not driven by
  automation; the underlying audio export was byte-for-byte checked.

## Scope

This is the first usable local speech studio. It uses the installed benchmark
Python runtime rather than bundling PyTorch into a distributable app. No timeline,
splicing, or consolidated editing UI is included. Stable takes and original WAVs
are retained for a later nondestructive editor.

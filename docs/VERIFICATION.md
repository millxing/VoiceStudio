# Verification — 2026-11-08

Installed release: `/Applications/VoiceStudio.app` (ad hoc signed), macOS 26.6.2,
M4 Max / 64 GB. Swift 6 language mode. No Swift source warnings. The installed
CLT emits linker warnings about missing Xcode framework search paths; documented
in README. No system toolchain files were changed.

## Cached voice importer update

- Current `tools/check.sh`: **21 library checks and 8 Python tests passed**.
  These include schema-one migration with original IDs/reference paths intact,
  cache persistence, Coqui and legacy formats, speaker-bank selection, bad
  dimensions/NaN/empty values, large checkpoints, and a pickle payload that is
  rejected without executing its command.
- `tools/cache-integration.sh`: **22 native integration checks passed**. Real
  XTTS tensors were imported as a Coqui cache and as a two-speaker bank; the
  selected speaker generated four MPS takes without any original recording.
  Playback, export, persistence, model reuse, and active cancellation passed.
- The reference-audio integration suite still passes all **17 checks**.
- App signature verification (`codesign --verify --deep --strict`) passed after
  cached import/generation. Python child processes use `-B`, so module imports
  cannot write bytecode into the signed application bundle.
- Add Voice's audio/cache source picker, cached-voice detail, Edit Cached Voice,
  reference-voice rows, and take source metadata were inspected in light/dark
  active-window screenshots. Grid lint and layout probes passed. The initial
  attempt targeted the main window while its edit sheet was key; the corrected
  targeted sheet captures are in `cache-import-screenshots/`.
- No real-user cache file was supplied. Fixtures used public XTTS conditioning
  tensors and nonexistent original-audio paths to verify independence from the
  recordings; actual likeness with the user's files still needs listening review.
- Existing manual microphone, external menu/hover and accessibility checks below
  remain manual. This feature adds no icon-only toolbar control.

See `verification/cache-*.log` and `cache-import-screenshots/` for evidence.

## Initial release automated results


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

This is the first usable local speech studio. It can retain a configured Python
runtime or download a managed runtime through first-run setup. PyTorch and the
model are downloaded separately from the app bundle. No timeline,
splicing, or consolidated editing UI is included. Stable takes and original WAVs
are retained for a later nondestructive editor.


## First-run installation verification — 2026-11-08

- Installed `/Applications/VoiceStudio.app`; Swift 6 release builds have no source
  warnings. The previously documented CLT linker search-path warnings remain.
- A fresh `/tmp/VoiceStudio-install.data/SpeechEngine` installed checksum-verified
  uv 0.11.31, managed Python 3.12.13, all 105 locked packages and XTTS-v2 with
  separate uv/Hugging Face caches. Child PATH contained only system directories;
  the existing benchmark Python, system uv and Homebrew were not used.
- This account's explicit prior CPML acceptance authorized the integration test.
  The test cannot run without `APP_TEST_CPML_ACCEPTED=1`. New-user setup still
  requires the unchecked consent control; the Python downloader rejects missing
  acceptance before importing TTS or creating installation files.
- Clean installation produced non-silent finite speech on strict MPS and ran
  reference conditioning before writing its receipt. Native queue integration
  then passed all 17 checks with that managed runtime/model, including multi-part
  cloned speech, multiple takes, playback, export, persistence and cancellation.
- Installer checks passed consent gating, cancellation, preserving the selected
  runtime, retry and adoption after validation. Quit during model installation
  exited successfully with no installer process left. AppKit terminateLater's
  nested-loop hang was caught and replaced with cancellation followed by quit
  from the normal event loop.
- 21 Swift library checks, 11 Python checks and 11 native basic checks passed.
  Python checks also ran under the newly installed runtime. Added reference
  decoder checks cover stereo/resampling/clipping and M4A via packaged FFmpeg;
  the M4A path asserts torchcodec is not imported.
- Inspected setup and Engine Settings in light/dark mode; no clipping in setup,
  disabled Install before consent, native scrollable full model terms. Removed
  an unwanted empty band caused by applying scroll sizing to the task VStack.
  Grid lint and every captured layout probe passed. Images are in
  `docs/setup-verification/`.
- The app bundle no longer contains a developer-account interpreter path.
  Existing saved interpreter preferences were preserved. The current Mac's
  working benchmark runtime is still selected.
- Full download was exercised on this Mac, not a second physical Mac. First-use
  Gatekeeper behavior, keyboard-only traversal and VoiceOver remain manual.

Reproduce: `APP_TEST_CPML_ACCEPTED=1 tools/install-integration.sh --cancel-install`
and `APP_TEST_CPML_ACCEPTED=1 tools/install-integration.sh --quit-install`, only
for an account whose user has explicitly accepted the bundled license.

# VoiceStudio

A native Mac app for local XTTS speech generation and voice cloning. Built with
BAMA's native macOS workflow for personal use on this M4 Max Mac Studio.

## Launch

Open `/Applications/VoiceStudio.app`. Complete setup if prompted. The engine then warms up in the background;
its status is shown at the bottom of the sidebar. Initial loading takes longer
than generating another take with the already-loaded model.

1. In **Voices**, choose **Add Voice…**. Name the voice and import one or more
   reference clips, or record your own microphone. Preview and save it. Use
   clean speech from one speaker; start with about 6–15 seconds per clip.
2. In **Scripts**, create a script or **Import Text Files…** (Command-O).
   Multiple files can be selected together. UTF-8 and UTF-16 with a byte-order
   mark are accepted; each file becomes an editable, autosaved script.
3. Select one or more scripts with Command-click or Shift-click. Choose a
   voice, language, speed, and **Takes** count (1–20 per script).
4. Choose **Generate Selected** (Command-G), or Speech > **Generate All**.
   Alternate takes have different random seeds. Work is processed sequentially.
5. In **Takes**, listen, seek, compare, **Export Take…** as WAV, or reveal it in
   Finder. Every take keeps its text, voice, model, speed, language, and seed.

### Import a saved XTTS voice (.pth)

In **Voices → Add Voice**, choose **Cached Voice (.pth)**, then
**Import Cached Voice…**. Select your saved voice file. If it contains multiple
speakers (such as `speakers_xtts.pth`), choose **Saved speaker**, give the voice a
name, and save it. Repeat for another speaker from the same file if needed.

The original reference recordings are not required. A cached voice contains
conditioning data rather than playable audio; generate a take to preview it.
Use the same XTTS model/checkpoint as the app that created the cache for the
closest results. VoiceStudio stores a validated local copy and leaves your
original file untouched; moving the original afterward is harmless.

Supported files include Coqui's `gpt_conditioning_latents` + `speaker_embedding`
cache, older `gpt_cond_latent` / `gpt_cond_latents` dictionaries, tensor pairs, and
named speaker banks. Loading uses PyTorch's restricted `weights_only=True` mode.
Unsupported pickle objects, other models, invalid tensor shapes/values, and model
checkpoints are rejected with an explanation. Full model files belong in
Settings > Engine, not the voice importer.

Existing version-one libraries upgrade automatically to version two while
retaining scripts, reference voices, and takes. Older app versions will reject
the upgraded library rather than dropping the new cached-voice fields.

**Stop Queue** cancels the current and queued work; completed takes stay saved.
A failed/canceled take can be retried as a new take with the same settings and
seed. Interrupted jobs become failed at next launch, and queued work can resume.
Long scripts are split at sentence/word boundaries within both the model's
character guidance and token limit, then joined with short pauses into one WAV
per take. Very long unbroken text is split as needed. This is generation, not an
editing timeline; splicing and assembly are planned separately.

## Engine and local data

Settings > Engine lets you choose Apple GPU (MPS) or CPU, a Python interpreter,
and an optional custom XTTS model folder containing `model.pth`, `config.json`,
and `vocab.json` (plus `speakers_xtts.pth` for built-in voices if available).
Custom models without built-in speakers can use cloned voice references.

On a new Apple Silicon Mac running macOS 26 or later, copy VoiceStudio to
`/Applications` and open it. The first-run **Install Speech Engine** sheet shows
the complete model license. Accept it and choose **Install Speech Engine**.
Allow about 8 GB of free space and several minutes for downloads and validation.
No Terminal, Homebrew, or separate Python installation is needed.

Setup installs a checksum-verified uv tool, an isolated Python 3.12 environment,
the locked speech packages, a bundled FFmpeg executable, and XTTS-v2 under
`~/Library/Application Support/VoiceStudio/SpeechEngine/`. It generates real
speech and checks voice conditioning before adopting the new runtime. Nothing
is added to your shell profile or system Python. VoiceStudio's `.app` contains
the installer and worker; the large runtime and model are downloaded separately.

Cancel stops the installer. Retry reuses downloaded packages and model files.
The Details disclosure shows the current log; the last 16 KB are also saved to
`SpeechEngine/install.log`. Reopen setup with **Speech → Install Speech Engine…**
(Option-Command-I), or **Settings → Engine → Install Speech Engine…**.
Your existing custom interpreter remains selected until installation succeeds.
You can still choose your own compatible Python interpreter or model folder in
Settings. New accounts must explicitly accept the model license themselves;
the app never silently accepts it.

The engine enables strict MPS without unsupported-operation CPU fallback; normal
preprocessing may still run on CPU. The first model download requires internet;
after installation, generation stays local. All 17 XTTS languages are offered;
Chinese and Japanese tokenizer dependencies are included in the runtime lock.
English speech generation is integration-tested; other languages need listening
review with your own scripts. Microphone recording needs first-use macOS consent.

Your scripts, voice-reference copies, settings, engine log, and WAV files live
under `~/Library/Application Support/VoiceStudio/`. Back up that folder. Source
text is stored in `Library.json`, so moving an imported text file is harmless.
Remove actions can be undone with Command-Z. Removing a voice/take from the
library retains its audio for Undo, existing takes, and future editing. This
first version does not automatically purge unused source audio.

## Build and verify

```sh
./build.sh --open
tools/check.sh        # Foundation library checks + worker chunk-boundary tests
tools/selftest.sh     # native app actions against /tmp storage
tools/integration.sh  # real multi-script, multiple-take MPS voice cloning
APP_TEST_CPML_ACCEPTED=1 tools/install-integration.sh # isolated first-run download/check
tools/cache-integration.sh # saved-cache import, bank selection, and GPU generation
tools/snap.sh        # every main page, voice sheet and Settings, light/dark
tools/grid-lint.sh
swift tools/check-layout.swift /tmp/VoiceStudio-shots/*-layout.json
```

All test stores use `/tmp`, never your real library. The installed CLT has stale
private PackageDescription interfaces, a macOS 27 SDK lacking SwiftUI macro
plugins, and no XCTest/Swift Testing macro runtime. Build scripts select the
installed macOS 26.5 SDK and use a local copy of PackageDescription support files
without the stale private interfaces; system tools are never modified. Library
checks use a small executable harness instead of unavailable testing frameworks.
The CLT build engine may print linker search-path warnings for absent Xcode
framework directories; these do not affect the application. Swift source builds
in Swift 6 mode without source warnings. On a full-Xcode Mac these workarounds
can be removed. The fallback app icon uses SF Symbols because Icon Composer's
`actool` is not available in this CLT install.

See `docs/BRIEF.md`, `docs/STORIES.md`, `docs/DESIGN.md`, and `docs/VERIFICATION.md`.
XTTS model terms are included in `Engine/XTTS-MODEL-LICENSE.txt`.

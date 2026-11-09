# VoiceStudio stories

## M1 — Local speech studio

### S-001 Write and retain scripts
Screens: scripts
Acceptance:
- [self] New Script, editing, and saved text survive reopening a test store.
- [snap] A script list and text editor display a selected script without clipping.
UX:
- Flow: ⌘N or New Script → selected script → edit title and text; autosave.
- Surface: sidebar page and inline detail, because scripts are revisited and edited repeatedly.
- States: empty offers New Script and Import Text Files; errors are inline and retain typed text.
- Access: named native editor and fields; all actions available by menu.
Status: done

### S-002 Import multiple text files
Screens: scripts
Acceptance:
- [self] Import two UTF-8/UTF-16 files; preserve content and names; reject empty/binary inputs with an explanation.
- [self] Select a subset or all scripts and enqueue takes in stable order.
UX:
- Flow: ⌘O / Import Text Files → multi-file system panel → imported scripts selected; Escape cancels.
- Surface: system open panel, because file selection must finish or cancel.
- States: per-file import errors; valid files still imported; list scrolls for large batches.
- Access: keyboard multi-selection, Generate Selected, and Generate All.
Status: done

### S-003 Create and preview cloned voices
Screens: voices, add-voice
Acceptance:
- [self] Add a named voice with multiple copied reference clips; preview and retain it after restart.
- [manual] Record a microphone clip, stop, preview and save it as a named voice. Implemented; first-use microphone/input-device check pending with the user.
- [self] Empty names and absent references cannot be saved.
UX:
- Flow: Add Voice → name plus Import Audio or Record → preview → Save Voice; Cancel discards temporary recording.
- Surface: sheet for creating one voice; sidebar/detail for managing the library.
- States: first-use microphone permission, recording timer, denied permission with fix, input validation.
- Access: labeled recording and import controls; Escape cancels; Return saves when valid.
Status: done

### S-004 Generate speech on the Apple GPU
Screens: scripts, takes, settings-engine
Acceptance:
- [self] Real native app launches the packaged worker, receives ready, and generates nonempty WAV on MPS.
- [self] Reference voice generation uses the same worker path as built-in generation.
- [self] Device, speed, language, model, and voice settings reach the worker.
UX:
- Flow: choose voice/language/speed → Generate Selected → queue state → completed take; Stop Queue cancels.
- Surface: inline generation controls; engine setup in Settings.
- States: loading model, running chunk, queued, ready, canceled, failed with retry and actionable errors.
- Access: ⌘G and labeled controls; status includes words, not color alone.
Status: done

### S-005 Generate alternate takes and batches
Screens: scripts, takes
Acceptance:
- [self] Two scripts × two takes creates four jobs with distinct seeds and immutable text snapshots.
- [self] Long text is chunked without dropping text or exceeding XTTS token limits.
- [self] Stop Queue and interruption retain completed work; failed work can be retried; pending work can resume after restart.
UX:
- Flow: select scripts → choose Takes per script → Generate Selected → track queue → compare takes.
- Surface: same generator controls; queue in Takes, never blocking modal progress.
- States: batch count, model loading, chunk progress, errors, completion.
- Access: Generate All has its own menu item; Stop Queue uses ⌘.; retries have visible text.
Status: done

### S-006 Listen, compare and export
Screens: takes
Acceptance:
- [self] Completed take metadata, WAV, text and seed persist; exporting copies the correct file.
- [manual] Playback, seeking, pause and voice preview passed through the native audio path; interactive autoplay and Finder reveal still need manual review.
- [snap] Take detail shows source text and settings for comparison and future editing.
UX:
- Flow: select take → Play/Pause, seek → Export or Show in Finder.
- Surface: native take detail; save panel for export.
- States: unavailable audio explains the missing file; playback progress; failed take exposes retry.
- Access: labeled transport, duration, slider, and shortcuts; no unlabeled icon-only toolbar controls.
Status: done

### S-007 Configure and recover the engine
Screens: settings-engine, settings-appearance
Acceptance:
- [self] Existing saved interpreters remain selected; managed runtime receipts restore configuration when preferences are absent. Paths remain configurable and persisted.
- [self] Bundled worker is loaded without requiring the source checkout; custom XTTS folder validation checks config and model files.
- [self] Worker crashes and invalid interpreters produce readable errors, not a frozen UI.
UX:
- Flow: Settings → Engine → choose Python/device/model → Restart Engine → status.
- Surface: native Settings tabs; paths are shown only here, where they help configure the engine.
- States: disconnected, starting, ready, unavailable; errors give a repair step.
- Access: native form labels and explicit restart command.
Status: done

## M2 — Saved voice import

### S-008 Import an XTTS cached voice
Screens: add-voice, cached-voice, edit-cached-voice, takes
Acceptance:
- [unit] Accept standard Coqui caches, supported legacy tensor names/pairs, and speaker banks; reject unsafe pickle objects, unrelated checkpoints and invalid tensors.
- [unit] Version-one libraries retain their contents when upgraded; new voices and takes persist their cached-voice paths.
- [self] Inspect and normalize a cached voice, select one speaker from a bank, and copy it into the library with no original audio present.
- [self] Generate multiple MPS takes using the saved conditioning, retain it in take snapshots, and reopen the results.
- [snap] Add/Edit Voice explains the Cached Voice source, speaker choice, and absence of playable reference audio in light/dark mode.
UX:
- Flow: Add Voice → Cached Voice (.pth) → Import Cached Voice → choose a speaker if needed → Save Voice → Use This Voice → Generate.
- Surface: existing voice task sheet, because this is another source for the same named voice; source selection is inline.
- States: no file, checking file, validated file, optional speaker choice, saving, and a readable import error. Cancel while inspecting cancels publication; Save is disabled until valid.
- Access: native labeled source picker, import button, optional speaker picker, Cancel/Save keyboard actions. No icon-only toolbar changes.
Status: done

## M3 — First-run installation

### S-009 Install the local speech engine
Screens: setup, settings-engine
Acceptance:
- [self] Fresh installation uses its own downloaded uv, managed Python, package cache and model files; it does not require the benchmark environment or Homebrew.
- [unit/self] Model download requires explicit CPML acceptance. Setup starts with an unchecked consent box and disabled Install action.
- [self] Generate real MPS speech and condition a voice before adopting the interpreter/model paths.
- [self] Cancel and quit stop installation; retry reuses downloads. Cancellation preserves existing runtime preferences.
- [unit] Decode stereo/resampled references and M4A using the bundled FFmpeg executable without importing torchcodec.
- [snap] Setup and Engine Settings are readable in light and dark mode.
UX:
- Flow: first launch without Python → review terms → accept → install → verified engine. Reopen from Speech or Settings.
- Surface: one task sheet with phase progress and expandable bounded log.
- States: consent required, downloading tools/Python/packages/model, verifying, cancelled/failed with retry, complete.
- Access: native labeled checkbox, buttons, progress indicator, selectable terms/log, menu shortcut Option-Command-I.
Status: done

## Later
- Timeline with nondestructive ranges, splicing, crossfades, and consolidated audio export.
- Model fine-tuning.

## Dropped
- Accounts, billing, cloud services, analytics, vendor onboarding.

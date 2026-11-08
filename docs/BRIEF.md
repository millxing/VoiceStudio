# VoiceStudio

A native, local Mac speech studio for Rob: clone voices, batch scripts, and compare alternate takes with XTTS.

## Replaces
xtts2-ui's Gradio interface. Existing benchmark proves MPS inference on this M4 Max.

## Main jobs
1. Write or import multiple text files and generate one or more takes per script.
2. Import or record named voice references, preview them, and clone them in 17 languages.
3. Listen to, compare, and export retained takes with their text and generation settings.

## Data
- Script: ID, title, text, creation date.
- Voice: ID, name, local reference files or imported XTTS cache, creation date.
- Take: ID, script snapshot, voice snapshot, language, speed, seed, audio path, status, duration, date, error.
- Preferences: device, model folder, runtime interpreter, autoplay, generation controls.

## Shape
Sidebar window, macOS 26 or later. Local application-support storage, no accounts. Offline after dependencies and model are installed.

## System hooks
Microphone recording, file import/export, Finder reveal, audio playback.

## Reference
Functional parity with BoltzmannEntropy/xtts2-ui (app.py and app2.py); native Mac layout rather than a visual clone.

## Look
Native SwiftUI with system accent. Calm, legible workspace. Decisions inferred from the request; no custom chrome.

## Not in version one
- Audio timeline, splicing, crossfades, and final assembly (future milestone).
- Training/fine-tuning models.
- Cloud accounts, sharing services, or billing.

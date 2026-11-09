# Design plan

- Archetype: native sidebar window with Scripts, Voices, and Takes. The script list supports multi-selection; the detail edits one script and offers shared generation options. Voices and Takes each have a list and detail.
- Information architecture: Scripts (editable source), Voices (named imported/recorded references), Takes (immutable generation history, including queued and failed work). Queue progress stays in the sidebar footer and in Takes.
- Feeling: calm and dependable. Native lists, text editor, grouped controls, system accent. Generation stays in the background. No invented progress percentages during model loading.
- Empty states: Scripts → New Script / Import Text Files; Voices → Add Voice; Takes → Generate speech from Scripts. Runtime errors show the fix in Settings.
- Commands: File > New Script (⌘N), Import Text Files (⌘O), Add Voice (⇧⌘V); Speech > Generate Selected (⌘G), Generate All (⇧⌘G), Stop Queue (⌘.); Playback > Play/Pause (⌥⌘P), Export Take (⇧⌘E), Show in Finder (⇧⌘R); View > Sidebar; Settings (⌘,). Controls that depend on selection are disabled when unavailable.
- Generation controls: voice, language, speed 0.10–1.99×, number of takes 1–20; default 1.0× and one take. Each take gets an independently chosen seed. Model and CPU/MPS selection live in Settings.
- Data: Atomically saved Codable JSON metadata, original/copied reference audio and WAV outputs in ~/Library/Application Support/VoiceStudio. Source text is stored in the database, so imports remain editable and survive moved source files. Takes retain snapshots, never references to mutable script text.
- Worker: one long-lived local Python process, JSON lines on dedicated stdout; logs on stderr; no server ports. Cache conditioning by reference content/version. Process death marks in-flight takes failed; queued jobs survive restart and require an explicit Resume Queue. Stop terminates the worker and marks remaining work canceled; completed takes remain.
- Future editor: stable take IDs and unmodified audio sources. Later edit decisions will reference source take ranges; no timeline or mock editing controls in this version.

## First-run speech engine installation

Missing/unusable Python opens a setup sheet, also reachable in Settings > Engine
and Speech > Install Speech Engine. An existing working interpreter remains an
advanced option. The sheet shows the complete bundled CPML and an unchecked
acceptance box. Install requires explicit acceptance before any model download.

Downloads are app-managed: a pinned official uv binary, managed Python 3.12,
locked Python packages with a packaged FFmpeg executable, and XTTS. No Homebrew,
shell-profile changes, administrator password, or Terminal commands are needed.
Phase progress and a bounded details log stay visible; cancellation interrupts
only setup's child process. Retry reuses download caches. Configure the interpreter
only after a real speech/decoder check succeeds; preserve custom runtimes.

All installation paths live under the selected library's SpeechEngine directory.
The installed app contains no developer-account path. A completion receipt and
per-install model-license acceptance record are stored locally. Test installs use
/tmp roots and their own Python/package/model caches, with consent inherited only
from the already accepted CPML on this account for integration testing.

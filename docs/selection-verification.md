# Multiple selection — 2026-11-10

Scripts already held a selection set, but each row's context menu generated or removed only that row. Source lists and the timeline held one ID. Lists now use native selection-aware context menus, source clips use a selection set, and timeline editing reads the complete selection.

- Scripts: Shift selects a range, Command toggles rows. Generate Selected, context-menu generation, context-menu removal, and list Delete use the selection.
- Clips and editor bin: native multiple selection, batch regeneration and removal. Add to Timeline places selected sources sequentially in displayed order as one undo step. Queued/running sources remain protected from removal and retry.
- Timeline: Shift-click adds, Command-click toggles, Command-A selects all. Delete, Shift-Delete, cut/copy/paste, movement, Option-drag duplication, and splitting use the selection. Paste preserves spacing and track positions and supports the previous single-clip clipboard. Empty-lane clicks clear selection. Text fields retain normal text editing.

Validation:

- Release build installed `/Applications/VoiceStudio.app`. Swift compilation succeeded; the local linker still reports the existing missing CommandLineTools search directories.
- `tools/check.sh`: 39 library checks and 11 Python tests passed.
- `tools/selftest.sh`: 84 checks passed, including rendered Shift-click, group movement, native batch clipboard operations, deletion/undo, source placement/removal, and regeneration of multiple sources.
- `tools/integration.sh`: 89 checks passed, including two scripts × two takes generated on MPS. Run before the final detail-pane button adjustment; the final self-test covers that adjustment's shared batch regeneration method.
- Grid lint and all six snapshot layout checks passed.
- Light/dark screenshots reviewed at `/tmp/VoiceStudio-shots/{scripts,takes,editor}-{light,dark}.png`, produced with `APP_SNAPSHOT_MULTI=1 APP_SNAPSHOT_PAGES=scripts,takes,editor tools/snap.sh`.

Scripts show two selected rows and the two-script generation count clearly in both appearances. Clips show two selected rows, a preview label, and Generate Selected Again without clipping. Editor shows two outlined timeline clips, two selected bin rows, and the selected count above its batch actions; waveforms remain readable in both appearances.

Visible hover for the revised Add to Timeline help text was not checked. No toolbar layout or icon changed.

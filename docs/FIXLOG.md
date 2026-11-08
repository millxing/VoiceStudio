# Fix log

## CLT template compatibility
Symptom: the stock BAMA scaffold did not compile on the installed command-line tools.
Cause: stale private PackageDescription interfaces, missing SwiftData/SwiftUI 27
macro plugins, and no test-framework runtime in this CLT installation.
Fix: use a local copy of manifest support without stale private interfaces,
select the installed macOS 26.5 SDK, use Codable persistence and an executable
library-check harness. Keep the system installation unchanged.
Rule: verify the actual SDK and compiler-plugin availability before choosing macro-dependent persistence.

## Undo after removing scripts
Symptom: scripts were restored but selection remained empty, so Generate Selected did nothing.
Cause: removal clears the selection, and the undo closure restored only documents.
Fix: restore the removed document IDs as selection along with their data.
Rule: restore the user's selection when undoing a bulk removal.

## Cancellation while microphone permission is pending
Symptom: permission completion could outlive a dismissed voice sheet.
Cause: the recorder task resumes after the asynchronous permission prompt.
Fix: a canceled recorder refuses to start when permission completes.
Rule: asynchronous permission results must respect dismissal and cancellation.

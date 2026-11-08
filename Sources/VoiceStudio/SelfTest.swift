import AppKit
import VoiceStudioKit

enum SelfTest {
    static var requested: Bool { CommandLine.arguments.contains("--selftest") }
    static var exitCode: Int32 = 0
    static var failures = 0
    static var count = 0
    static func check(_ name: String, _ ok: Bool) {
        count += 1; if !ok { failures += 1 }
        FileHandle.standardOutput.write(Data("\(ok ? "PASS" : "FAIL") \(name)\n".utf8))
    }
    static func runIfRequested(model: AppModel) {
        guard requested else { return }
        guard Store.isOverridden else { finish(code: 1); return }
        Task {
            let base = model.scripts.count
            model.addScript()
            check("New Script selects a retained document", model.scripts.count == base + 1 && model.selectedScript != nil)
            guard let id = model.selectedScript?.id else { finish(code: 1); return }
            model.updateScript(id, title: "Self-test", text: "This is a local speech test. The studio is ready to tell a new story.")
            do {
                try FileManager.default.createDirectory(at: Store.root, withIntermediateDirectories: true)
                let temp = Store.root.appending(path: "Import.txt")
                try "A second script for batch generation.".write(to: temp, atomically: true, encoding: .utf8)
                let unicode = Store.root.appending(path: "Unicode.txt")
                try "Bonjour, le monde.".write(to: unicode, atomically: true, encoding: .utf16)
                model.importScripts([temp, unicode])
                check("Multiple text imports select both documents", model.selectedScripts.count == 2)
                let saved = try LibraryFile.load(from: Store.url)
                check("Library survives reopening", saved.scripts.count == base + 3 && saved.scripts.first { $0.id == id }?.title == "Self-test")
                let undo = UndoManager()
                let selected = model.selectedScripts
                model.removeScripts(selected, undo: undo)
                undo.undo()
                check("Removing scripts can be undone", selected.isSubset(of: Set(model.scripts.map(\.id))))
                if let sample = Bundle.main.resourceURL?.appending(path: "demo-reference.wav") {
                    try model.storeVoice(name: "Test narrator", urls: [sample, sample], existing: nil)
                    check("Voice copies multiple references", model.voices.last?.files.count == 2)
                }
                if CommandLine.arguments.contains("--integration") {
                    // Exercise the same queue and worker the UI uses, with distinct seeds.
                    let longText = "This is a local speech test. The studio is ready to tell a new story. " + String(repeating: "Outside, the city was beginning to wake up, and somewhere in the distance a train was passing. ", count: 4)
                    model.updateScript(id, text: longText)
                    let second = model.scripts.first { $0.id != id }!.id
                    model.selectedScripts = [id, second]
                    model.preferences.takes = 2
                    model.preferences.device = "mps"
                    model.queue()
                    model.updateScript(id, text: "Changed after enqueue.")
                    let pending = model.library.takes
                    check("Two scripts × two takes have distinct seeds and immutable text", pending.count == 4 && Set(pending.map(\.seed)).count == 4 && pending.allSatisfy { !$0.text.contains("Changed") })
                    let deadline = Date().addingTimeInterval(180)
                    while model.queueRunning && Date() < deadline { try await Task.sleep(for: .milliseconds(200)) }
                    check("Native app generates cloned voice takes on MPS", model.library.takes.count == 4 && model.library.takes.allSatisfy { $0.status == .completed && $0.duration > 0 })
                    if let take = model.library.takes.first, take.status == .completed {
                        try model.playback.toggle(Store.root.appending(path: take.audioFile))
                        try await Task.sleep(for: .milliseconds(300))
                        check("Generated WAV opens and playback timer advances", model.playback.duration > 0 && model.playback.position > 0)
                        try model.playback.toggle(Store.root.appending(path: take.audioFile))
                        check("Native playback pauses", !model.playback.isPlaying)
                        try model.playback.toggle(Store.root.appending(path: take.audioFile))
                        check("Native playback resumes", model.playback.isPlaying)
                        model.playback.seek(0.2); model.playback.stop()
                        let exported = Store.root.appending(path: "Exported.wav")
                        try model.copyTake(take, to: exported)
                        check("Export copies the correct audio", try Data(contentsOf: exported) == Data(contentsOf: Store.root.appending(path: take.audioFile)))
                    }
                    for take in model.library.takes where take.status != .completed { print("DETAIL \(take.status) \(take.error)") }
                    check("Metadata and completed audio survive reopen", try LibraryFile.load(from: Store.url).takes.allSatisfy { $0.status == .completed })
                    model.selectedScripts = [id]; model.preferences.takes = 1
                    model.queue()
                    check("Queue starts another take without reloading the model", model.activeTake != nil)
                    model.stopQueue()
                    check("Stop Queue cancels active generation", !model.queueRunning && model.activeTake == nil && model.library.takes.last?.status == .canceled)
                    model.engine.stop()
                } else {
                    // Enqueue with a deliberately absent interpreter; jobs stay recoverable.
                    model.preferences.python = "/tmp/VoiceStudio-no-python"
                    model.preferences.takes = 2
                    model.queue()
                    check("Two scripts create four recoverable takes", model.library.takes.count == 4 && model.library.takes.allSatisfy { $0.status == .queued })
                    check("Missing interpreter reports an actionable error", !model.engine.lastError.isEmpty && !model.queueRunning)
                    model.stopQueue()
                    check("Stop Queue cancels pending work", model.library.takes.allSatisfy { $0.status == .canceled })
                }
                for page in SidebarItem.allCases { check("Valid symbol: \(page.symbol)", NSImage(systemSymbolName: page.symbol, accessibilityDescription: nil) != nil) }
            } catch { check("Self-test error: \(error.localizedDescription)", false) }
            print("SELFTEST \(failures == 0 ? "PASS" : "FAIL") \(count) checks")
            finish(code: failures == 0 ? 0 : 1)
        }
    }
    static func finish(code: Int32) {
        exitCode = code
        for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
        NSApp.terminate(nil)
    }
}

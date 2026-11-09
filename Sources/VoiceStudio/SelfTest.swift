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
            if CommandLine.arguments.contains("--settings-check") {
                do {
                    let folder = Store.root.deletingLastPathComponent().appending(path: "VoiceStudio-settings-output")
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try model.setTakesFolder(folder)
                    model.preferences.python = "/tmp/VoiceStudio-no-python"
                    model.addScript()
                    let script = model.selectedScript!
                    model.updateScript(script.id, text: "A focused storage check.")
                    model.queue()
                    let take = model.library.takes.last!
                    check("New takes retain the selected output folder", take.audioURL(relativeTo: Store.root).deletingLastPathComponent().standardizedFileURL.path == folder.standardizedFileURL.path)
                    try Data("test audio bytes".utf8).write(to: take.audioURL(relativeTo: Store.root))
                    let exported = folder.appending(path: "export-check.wav")
                    try model.copyTake(take, to: exported)
                    check("Export reads the selected takes folder", try Data(contentsOf: exported) == Data("test audio bytes".utf8))
                    try model.setTakesFolder(nil)
                    check("Changing the folder preserves existing take locations", take.audioURL(relativeTo: Store.root).deletingLastPathComponent().standardizedFileURL.path == folder.standardizedFileURL.path)
                    let legacy = SpeechTake(script: script, voiceName: "Voice", speaker: "", references: [], language: "en", speed: 1, seed: 1, modelFolder: "", device: "cpu", number: 1)
                    check("Existing relative audio paths still resolve inside the library", legacy.audioURL(relativeTo: Store.root) == Store.root.appending(path: legacy.audioFile))
                    var older = StudioLibrary(); older.schemaVersion = 2; older.takes = [legacy]
                    let migration = Store.root.appending(path: "migration-check.json")
                    try LibraryFile.save(older, to: migration)
                    check("Version-two libraries retain audio paths when upgraded", try LibraryFile.load(from: migration).takes.first?.audioFile == legacy.audioFile)
                    let oldPreferences = try JSONEncoder().encode(StudioPreferences())
                    check("Preferences without a takes folder decode", try JSONDecoder().decode(StudioPreferences.self, from: oldPreferences).takesFolder == nil)
                } catch { check("Focused settings check: \(error.localizedDescription)", false) }
                finish(code: failures == 0 ? 0 : 1); return
            }
            if CommandLine.arguments.contains("--install-engine") {
                // This account's explicit prior CPML consent is required by the test runner.
                guard ProcessInfo.processInfo.environment["APP_TEST_CPML_ACCEPTED"] == "1" else { finish(code: 1); return }
                model.installer.install(accepted: false) {}
                check("Installation cannot start without consent", !model.installer.running)
                if CommandLine.arguments.contains("--quit-install") {
                    model.installer.install(accepted: true) {}
                    let deadline = Date().addingTimeInterval(60)
                    while model.installer.running && !model.installer.status.contains("checking XTTS") && Date() < deadline {
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                    guard model.installer.running && model.installer.status.contains("checking XTTS") else { finish(code: 1); return }
                    print("PASS Quit requested during active model installation")
                    NSApp.terminate(nil); return
                }
                if CommandLine.arguments.contains("--cancel-install") {
                    let original = model.preferences
                    model.installer.install(accepted: true) {}
                    try? await Task.sleep(for: .milliseconds(100))
                    model.installer.cancel()
                    while model.installer.running { try? await Task.sleep(for: .milliseconds(100)) }
                    check("Cancel stops installation before retry", !model.installer.completed && model.installer.error.contains("cancelled"))
                    check("Cancellation preserves the selected runtime", model.preferences == original)
                }
                model.installer.install(accepted: true) { model.adoptInstalledEngine() }
                while model.installer.running { try? await Task.sleep(for: .seconds(1)) }
                check("Clean managed installation generates speech and conditions a voice", model.installer.completed)
                check("Verified interpreter is adopted", model.preferences.python == model.installer.python.path && model.installer.receipt != nil)
                if !model.installer.error.isEmpty { print(model.installer.error, model.installer.details) }
                finish(code: failures == 0 ? 0 : 1); return
            }
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
                if let fixture = ProcessInfo.processInfo.environment["APP_CACHE_FIXTURE"] {
                    let source = URL(fileURLWithPath: fixture)
                    let entries = try await CachedVoiceImport.inspect(source, python: model.preferences.python)
                    check("Inspect a Coqui cached voice without loading the speech model", entries.count == 1)
                    try await model.storeCachedVoice(name: "Imported cache", source: source, entry: entries[0].id, existing: nil)
                    check("Cached voice is copied into the library without reference audio", model.voices.last?.cachedFile != nil && model.voices.last?.files.isEmpty == true)
                    if let bank = ProcessInfo.processInfo.environment["APP_CACHE_BANK"] {
                        let bankURL = URL(fileURLWithPath: bank)
                        let speakers = try await CachedVoiceImport.inspect(bankURL, python: model.preferences.python)
                        check("Speaker bank presents both saved speakers", speakers.map(\.id).sorted() == ["Narrator A", "Narrator B"])
                        try await model.storeCachedVoice(name: "Imported bank speaker", source: bankURL, entry: "Narrator B", existing: nil)
                        check("Selected bank speaker survives saving and reopening", try LibraryFile.load(from: Store.url).voices.last?.cachedFile == model.voices.last?.cachedFile)
                    }
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
                    if ProcessInfo.processInfo.environment["APP_CACHE_FIXTURE"] != nil {
                        check("Queued takes retain cached voice snapshots", pending.allSatisfy { $0.cachedVoice != nil && $0.references.isEmpty })
                    }
                    check("Two scripts × two takes have distinct seeds and immutable text", pending.count == 4 && Set(pending.map(\.seed)).count == 4 && pending.allSatisfy { !$0.text.contains("Changed") })
                    let deadline = Date().addingTimeInterval(180)
                    while model.queueRunning && Date() < deadline { try await Task.sleep(for: .milliseconds(200)) }
                    check("Native app generates cloned voice takes on MPS", model.library.takes.count == 4 && model.library.takes.allSatisfy { $0.status == .completed && $0.duration > 0 })
                    if let take = model.library.takes.first, take.status == .completed {
                        try model.playback.toggle(take.audioURL(relativeTo: Store.root))
                        try await Task.sleep(for: .milliseconds(300))
                        check("Generated WAV opens and playback timer advances", model.playback.duration > 0 && model.playback.position > 0)
                        try model.playback.toggle(take.audioURL(relativeTo: Store.root))
                        check("Native playback pauses", !model.playback.isPlaying)
                        try model.playback.toggle(take.audioURL(relativeTo: Store.root))
                        check("Native playback resumes", model.playback.isPlaying)
                        model.playback.seek(0.2); model.playback.stop()
                        let exported = Store.root.appending(path: "Exported.wav")
                        try model.copyTake(take, to: exported)
                        check("Export copies the correct audio", try Data(contentsOf: exported) == Data(contentsOf: take.audioURL(relativeTo: Store.root)))
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
                try await editorChecks(model)
                check("Sidebar order is Scripts, Takes, Editor, Voices", SidebarItem.allCases == [.scripts, .takes, .editor, .voices])
                for page in SidebarItem.allCases { check("Valid symbol: \(page.symbol)", NSImage(systemSymbolName: page.symbol, accessibilityDescription: nil) != nil) }
            } catch { check("Self-test error: \(error.localizedDescription)", false) }
            print("SELFTEST \(failures == 0 ? "PASS" : "FAIL") \(count) checks")
            finish(code: failures == 0 ? 0 : 1)
        }
    }
    /// Arranges two takes on two tracks, splices them, and exports the mix.
    static func editorChecks(_ model: AppModel) async throws {
        var made = [SpeechTake]()
        for (index, seconds) in [2.0, 3.0].enumerated() {
            var take = SpeechTake(script: ScriptDocument(title: "Editor \(index + 1)", text: "Editor test."), voiceName: "Test", speaker: "Test",
                                  references: [], language: "en", speed: 1, seed: index, modelFolder: "", device: "cpu", number: 1)
            let audio = SeedData.speechLike(seconds: seconds, seed: UInt64(index + 7))
            try FileManager.default.createDirectory(at: take.audioURL(relativeTo: Store.root).deletingLastPathComponent(), withIntermediateDirectories: true)
            try TimelineAudio.writeWAV(audio, to: take.audioURL(relativeTo: Store.root))
            take.status = .completed; take.duration = seconds
            model.library.takes.append(take); made.append(take)
        }
        model.sidebar = .editor
        let undo = UndoManager()
        model.addToTimeline(made[0], track: 0, undo: undo)
        model.addToTimeline(made[1], track: 1, at: 0.5, undo: undo)
        check("Editor places takes on separate tracks", model.timeline.clips.map(\.track) == [0, 1] && abs(model.timeline.duration - 3.5) < 0.01)
        model.loadWaveforms()
        check("Editor draws waveforms for placed takes", made.allSatisfy { !(model.waveforms[$0.id] ?? []).isEmpty })
        let first = model.timeline.clips[0].id
        model.selectedClip = first; model.seekTimeline(1)
        model.splitAtPlayhead(undo: undo)
        check("Split at playhead cuts the selected clip only", model.timeline.clips.count == 3)
        let ripple = UndoManager()
        model.deleteClip(ripple: true, undo: ripple)
        check("Ripple delete closes the gap on its track", model.timeline.clips(on: 0).first.map { abs($0.start) < 0.001 && abs($0.inPoint - 1) < 0.001 } == true)
        ripple.undo()
        check("Editor changes can be undone", model.timeline.clips.count == 3)
        model.playback.loops = true
        model.toggleTimelinePlayback()
        try await Task.sleep(for: .milliseconds(300))
        check("Timeline preview plays with looping", model.isPlayingTimeline && model.playback.isPlaying && model.timelineTime > 0)
        model.toggleTimelinePlayback()
        check("Timeline preview pauses", !model.playback.isPlaying)
        model.playback.stop(); model.playback.loops = false
        let wav = Store.root.appending(path: "Timeline.wav")
        try model.exportTimeline(.wav, to: wav)
        check("Export mixes every track into one WAV", abs(try AudioValidation.validate(wav) - model.timeline.duration) < 0.01)
        if TimelineAudio.mp3Encoder != nil {
            let mp3 = Store.root.appending(path: "Timeline.mp3")
            try model.exportTimeline(.mp3, to: mp3)
            check("Export writes a readable MP3", abs(try AudioValidation.validate(mp3) - model.timeline.duration) < 0.2)
        } else { print("SKIP MP3 export: no LAME or FFmpeg installed") }
        model.setTrack(0, muted: true, undo: undo); model.setTrack(1, muted: true, undo: undo)
        check("Muting every track leaves nothing to export", (try? model.exportTimeline(.wav, to: wav)) == nil)
        model.setTrack(0, muted: false, undo: undo); model.setTrack(1, muted: false, undo: undo)
        check("The timeline survives reopening", try LibraryFile.load(from: Store.url).timeline == model.timeline)
    }
    static func finish(code: Int32) {
        exitCode = code
        for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
        NSApp.terminate(nil)
    }
}

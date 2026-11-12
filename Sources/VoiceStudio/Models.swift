import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers
import VoiceStudioKit

enum Store {
    static var isOverridden: Bool { ProcessInfo.processInfo.environment["APP_STORE"] != nil }
    static var url: URL {
        if let path = ProcessInfo.processInfo.environment["APP_STORE"] { return URL(fileURLWithPath: path) }
        return root.appending(path: "Library.json")
    }
    static var root: URL {
        if let path = ProcessInfo.processInfo.environment["APP_STORE"] {
            return URL(fileURLWithPath: path).deletingPathExtension().appendingPathExtension("data")
        }
        return URL.applicationSupportDirectory.appending(path: "VoiceStudio", directoryHint: .isDirectory)
    }
}
enum SidebarItem: String, CaseIterable, Identifiable {
    case scripts, takes, editor, voices
    var id: String { rawValue }
    var title: String { self == .takes ? "Clips" : rawValue.capitalized }
    var symbol: String {
        switch self { case .scripts: "doc.text"; case .takes: "waveform"; case .editor: "slider.horizontal.below.rectangle"; case .voices: "person.wave.2" }
    }
}
struct StudioPreferences: Codable, Equatable {
    var python = ""
    var device = "mps"
    var modelFolder = ""
    var voice = "builtin:Craig Gutsy"
    var language = "en"
    var speed = 1.0
    var takes = 1
    var autoplay = false
    var takesFolder: String?
    var exportFolder: String?
    /// Script editor text size in points. Optional, so settings saved before it existed still load.
    var scriptFontSize: Double?
    static let defaultScriptFontSize = 26.0
    static let scriptFontSizes = 10.0...72.0
    var scriptFont: Double {
        get { scriptFontSize ?? Self.defaultScriptFontSize }
        set { scriptFontSize = min(max(newValue, Self.scriptFontSizes.lowerBound), Self.scriptFontSizes.upperBound) }
    }
}
@Observable
final class AppModel {
    var library = StudioLibrary() { didSet { save() } }
    var preferences = StudioPreferences() { didSet { savePreferences() } }
    var sidebar: SidebarItem? = .scripts { didSet { saveSession() } }
    var selectedScripts = Set<UUID>() { didSet { saveSession() } }
    var selectedVoice: UUID? { didSet { saveSession() } }
    var selectedTakes = Set<UUID>() { didSet { saveSession() } }
    var selectedTake: UUID? {
        get { takes.first { selectedTakes.contains($0.id) }?.id }
        set { selectedTakes = Set(newValue.map { [$0] } ?? []) }
    }
    var settingsTab: SettingsTab = .engine
    let installer = EngineInstaller()
    var showingEngineSetup = false
    var showingVoiceSheet = false
    var editingVoice: VoiceReference?
    var message = ""
    var queueRunning = false
    var activeTake: UUID?
    var progress = ""
    var completedInBatch = 0
    var batchTotal = 0
    let engine = SpeechEngine()
    let playback = AudioPlayback()
    // Editor state. The arrangement itself lives in `library.timeline`.
    var selectedClips = Set<UUID>()
    var selectedClip: UUID? {
        get { timeline.clips.first { selectedClips.contains($0.id) }?.id }
        set { selectedClips = Set(newValue.map { [$0] } ?? []) }
    }
    var playhead = 0.0
    var zoom = 40.0
    var waveforms: [UUID: [Float]] = [:]
    @ObservationIgnored var sampleCache: [UUID: [Float]] = [:]
    var timelineRender: URL?
    var timelinePlaybackOrigin = 0.0
    var timelineRevealRequest = UUID()
    @ObservationIgnored private var saveEnabled = false
    @ObservationIgnored private var canWrite = true
    @ObservationIgnored private var startingJob: SpeechTake?

    var scripts: [ScriptDocument] { library.scripts }
    var voices: [VoiceReference] { library.voices }
    var takes: [SpeechTake] { library.takes.sorted { $0.createdAt > $1.createdAt } }
    var queuedCount: Int { library.takes.filter { $0.status == .queued }.count }
    var selectedScript: ScriptDocument? { scripts.first { selectedScripts.contains($0.id) } }
    var take: SpeechTake? { takes.first { $0.id == selectedTake } }
    var voice: VoiceReference? { voices.first { $0.id == selectedVoice } }
    var canGenerate: Bool { scripts.contains { selectedScripts.contains($0.id) && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } && canWrite }
    var logURL: URL { Store.root.appending(path: "Engine.log") }

    init() {
        do {
            library = try LibraryFile.load(from: Store.url)
            library.recoverInterrupted()
        } catch {
            canWrite = false
            message = "Unable to open the library: \(error.localizedDescription) The original file has been preserved."
        }
        let prefURL = Store.root.appending(path: "Preferences.json")
        if let data = try? Data(contentsOf: prefURL), let saved = try? JSONDecoder().decode(StudioPreferences.self, from: data) {
            preferences = saved
        }
        if Store.isOverridden, let python = ProcessInfo.processInfo.environment["VOICE_PYTHON"] {
            preferences.python = python
        } else if preferences.python.isEmpty, let receipt = installer.receipt {
            preferences.python = receipt["python"] ?? ""
            preferences.modelFolder = receipt["modelFolder"] ?? ""
            preferences.device = receipt["device"] ?? "mps"
        }
        if let data = try? Data(contentsOf: Store.root.appending(path: "Session.json")),
           let session = try? JSONDecoder().decode([String: String].self, from: data) {
            sidebar = SidebarItem(rawValue: session["page"] ?? "") ?? .scripts
            selectedScripts = Set((session["scripts"] ?? "").split(separator: ",").compactMap { UUID(uuidString: String($0)) })
            selectedVoice = UUID(uuidString: session["voice"] ?? "")
            selectedTakes = Set((session["takes"] ?? session["take"] ?? "").split(separator: ",").compactMap { UUID(uuidString: String($0)) })
        }
        saveEnabled = true
        engine.onEvent = { [weak self] event in self?.handle(event) }
    }
    func save() {
        guard saveEnabled, canWrite else { return }
        do { try LibraryFile.save(library, to: Store.url) }
        catch { message = "Unable to save the library: \(error.localizedDescription)" }
    }
    private func saveSession() {
        guard saveEnabled else { return }
        let session = ["page": sidebar?.rawValue ?? "scripts", "scripts": selectedScripts.map(\.uuidString).sorted().joined(separator: ","),
                       "voice": selectedVoice?.uuidString ?? "", "takes": selectedTakes.map(\.uuidString).sorted().joined(separator: ",")]
        do {
            try FileManager.default.createDirectory(at: Store.root, withIntermediateDirectories: true)
            try JSONEncoder().encode(session).write(to: Store.root.appending(path: "Session.json"), options: .atomic)
        } catch { message = "Unable to restore the workspace next time: \(error.localizedDescription)" }
    }
    private func savePreferences() {
        guard saveEnabled else { return }
        do {
            try FileManager.default.createDirectory(at: Store.root, withIntermediateDirectories: true)
            try JSONEncoder().encode(preferences).write(to: Store.root.appending(path: "Preferences.json"), options: .atomic)
        } catch { message = "Unable to save settings: \(error.localizedDescription)" }
    }
    func addScript() {
        let script = ScriptDocument(title: ScriptDocument.defaultTitle())
        library.scripts.append(script)
        sidebar = .scripts; selectedScripts = [script.id]
    }
    func updateScript(_ id: UUID, title: String? = nil, text: String? = nil) {
        guard let i = library.scripts.firstIndex(where: { $0.id == id }) else { return }
        var script = library.scripts[i]
        if let title { script.title = title }
        if let text { script.text = text }
        guard script != library.scripts[i] else { return }
        script.modifiedAt = Date()
        library.scripts[i] = script
    }
    /// Copies the scripts and inserts the copies at `index`, or after the last original.
    /// The copies become the selection.
    func duplicateScripts(_ ids: Set<UUID>, at index: Int? = nil, undo: UndoManager?) {
        let originals = library.scripts.filter { ids.contains($0.id) }
        guard !originals.isEmpty else { return }
        let copies = originals.map { $0.duplicate() }
        let last = library.scripts.lastIndex { ids.contains($0.id) } ?? library.scripts.count - 1
        let at = min(max(0, index ?? last + 1), library.scripts.count)
        library.scripts.insert(contentsOf: copies, at: at)
        sidebar = .scripts; selectedScripts = Set(copies.map(\.id))
        let copyIDs = Set(copies.map(\.id))
        undo?.registerUndo(withTarget: self) { model in
            model.library.scripts.removeAll { copyIDs.contains($0.id) }
            model.selectedScripts = ids
        }
        undo?.setActionName(copies.count == 1 ? "Duplicate Script" : "Duplicate Scripts")
    }
    /// A drag in the script list. Option duplicates the dragged scripts; a plain drag reorders them.
    func dropScripts(_ offsets: IndexSet, to destination: Int, copy: Bool, undo: UndoManager?) {
        let ids = Set(offsets.compactMap { library.scripts.indices.contains($0) ? library.scripts[$0].id : nil })
        if copy { duplicateScripts(ids, at: destination, undo: undo); return }
        let order = library.scripts.map(\.id)
        library.scripts.move(fromOffsets: offsets, toOffset: destination)
        guard library.scripts.map(\.id) != order else { return }
        // Undo restores the order only, so later text edits stay.
        undo?.registerUndo(withTarget: self) { model in
            let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
            model.library.scripts.sort { (rank[$0.id] ?? .max) < (rank[$1.id] ?? .max) }
        }
        undo?.setActionName("Move Scripts")
    }
    func importScripts() {
        let panel = NSOpenPanel()
        panel.title = "Import Text Files"; panel.allowedContentTypes = [.plainText, .text]
        panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        importScripts(panel.urls)
    }
    func importScripts(_ urls: [URL]) {
        var imported = Set<UUID>(), errors = [String]()
        for url in urls {
            do {
                let script = try LibraryFile.readScript(at: url)
                library.scripts.append(script); imported.insert(script.id)
            } catch { errors.append(error.localizedDescription) }
        }
        if !imported.isEmpty { selectedScripts = imported; sidebar = .scripts }
        if !errors.isEmpty { message = errors.joined(separator: "\n") }
    }
    func removeScripts(_ ids: Set<UUID>, undo: UndoManager?) {
        let removed = library.scripts.enumerated().filter { ids.contains($0.element.id) }
        library.scripts.removeAll { ids.contains($0.id) }
        selectedScripts.subtract(ids)
        undo?.registerUndo(withTarget: self) { model in
            for (index, script) in removed { model.library.scripts.insert(script, at: min(index, model.library.scripts.count)) }
            model.selectedScripts = Set(removed.map { $0.element.id })
        }
        undo?.setActionName("Remove Scripts")
    }
    func addVoice() { editingVoice = nil; showingVoiceSheet = true }
    func storeVoice(name: String, urls: [URL], existing: VoiceReference?) throws {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, !urls.isEmpty else { throw LibraryFile.failure("Give the voice a name and at least one reference clip.") }
        var voice = existing ?? VoiceReference(name: cleaned, files: [])
        let folder = Store.root.appending(path: "Voices/\(voice.id.uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var files = [String]()
        for url in urls {
            let asset = try AudioValidation.validate(url)
            guard asset >= 0.33 else { throw LibraryFile.failure("\(url.lastPathComponent) is too short. Use at least a few seconds of speech.") }
            if let file = existing?.files.first(where: { Store.root.appending(path: $0).standardizedFileURL == url.standardizedFileURL }) {
                files.append(file)
            } else {
                let file = "Voices/\(voice.id.uuidString)/\(UUID().uuidString).\(url.pathExtension.lowercased())"
                try FileManager.default.copyItem(at: url, to: Store.root.appending(path: file))
                files.append(file)
            }
        }
        voice.name = cleaned; voice.files = files; voice.cachedFile = nil
        if let i = library.voices.firstIndex(where: { $0.id == voice.id }) { library.voices[i] = voice }
        else { library.voices.append(voice) }
        selectedVoice = voice.id; preferences.voice = "clone:\(voice.id.uuidString)"
        sidebar = .voices
    }
    func storeCachedVoice(name: String, source: URL, entry: String, existing: VoiceReference?) async throws {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw LibraryFile.failure("Give the voice a name.") }
        var voice = existing ?? VoiceReference(name: cleaned, files: [])
        let file = "Voices/\(voice.id.uuidString)/\(UUID().uuidString).pth"
        let destination = Store.root.appending(path: file)
        do {
            try await CachedVoiceImport.convert(source, entry: entry, destination: destination, python: preferences.python)
            try Task.checkCancellation()
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        voice.name = cleaned; voice.files = []; voice.cachedFile = file
        if let index = library.voices.firstIndex(where: { $0.id == voice.id }) { library.voices[index] = voice }
        else { library.voices.append(voice) }
        selectedVoice = voice.id; preferences.voice = "clone:\(voice.id.uuidString)"; sidebar = .voices
    }
    func removeVoice(_ voice: VoiceReference, undo: UndoManager?) {
        library.voices.removeAll { $0.id == voice.id }; selectedVoice = nil
        if preferences.voice == "clone:\(voice.id.uuidString)" { preferences.voice = "builtin:Craig Gutsy" }
        // Retain source audio, because completed and queued takes reference it.
        undo?.registerUndo(withTarget: self) { model in model.library.voices.append(voice) }
        undo?.setActionName("Remove Voice")
    }
    var takesFolder: URL {
        preferences.takesFolder.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? Store.root.appending(path: "Audio", directoryHint: .isDirectory)
    }
    func setTakesFolder(_ folder: URL?) throws {
        guard !queueRunning else { throw LibraryFile.failure("Stop the queue before changing the clips folder.") }
        if let folder { try validateTakesFolder(folder) }
        preferences.takesFolder = folder?.standardizedFileURL.path
    }
    private func validateTakesFolder(_ folder: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw LibraryFile.failure("The clips folder is unavailable. Reconnect the drive or choose a folder in Settings > Storage.")
        }
        let probe = folder.appending(path: ".VoiceStudio-\(UUID().uuidString).tmp")
        do {
            try Data().write(to: probe, options: .atomic)
            try FileManager.default.removeItem(at: probe)
        } catch { throw LibraryFile.failure("VoiceStudio cannot write to this clips folder. Choose another folder in Settings > Storage.") }
    }
    private func prepareTakeStorage() -> Bool {
        do {
            if preferences.takesFolder == nil { try FileManager.default.createDirectory(at: takesFolder, withIntermediateDirectories: true) }
            try validateTakesFolder(takesFolder)
            return true
        } catch { message = error.localizedDescription; return false }
    }
    private func setOutputLocation(_ take: inout SpeechTake) {
        if preferences.takesFolder != nil { take.audioFile = takesFolder.appending(path: "\(take.id.uuidString).wav").path }
    }
    func queue(all: Bool = false) {
        guard canWrite, prepareTakeStorage() else { return }
        let documents = scripts.filter { (all || selectedScripts.contains($0.id)) && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !documents.isEmpty else { message = "Write or import a script before generating speech."; return }
        var speaker = "", references = [String](), name = ""
        var cachedVoice: String?
        if preferences.voice.hasPrefix("clone:"), let voice = voices.first(where: { "clone:\($0.id.uuidString)" == preferences.voice }) {
            references = voice.files; name = voice.name; cachedVoice = voice.cachedFile
        } else if preferences.voice.hasPrefix("builtin:") {
            speaker = String(preferences.voice.dropFirst(8)); name = speaker
        } else { message = "Choose a voice before generating speech."; return }
        for script in documents {
            let last = library.takes.filter { $0.scriptID == script.id }.map(\.number).max() ?? 0
            for n in 1...max(1, min(20, preferences.takes)) {
                var take = SpeechTake(script: script, voiceName: name, speaker: speaker, references: references,
                    language: preferences.language, speed: preferences.speed, seed: Int.random(in: 1...Int(Int32.max)),
                    modelFolder: preferences.modelFolder, device: preferences.device, number: last + n, cachedVoice: cachedVoice)
                setOutputLocation(&take)
                library.takes.append(take)
                if selectedTake == nil { selectedTake = take.id }
            }
        }
        if !queueRunning { completedInBatch = 0; batchTotal = queuedCount }
        else { batchTotal += documents.count * preferences.takes }
        queueRunning = true
        next()
    }
    func resumeQueue() {
        guard queuedCount > 0, !queueRunning else { return }
        completedInBatch = 0; batchTotal = queuedCount; queueRunning = true; next()
    }
    func adoptInstalledEngine() {
        guard let receipt = installer.receipt else { return }
        preferences.python = receipt["python"] ?? ""
        preferences.modelFolder = receipt["modelFolder"] ?? ""
        preferences.device = receipt["device"] ?? "mps"
        if !Store.isOverridden { restartEngine() }
    }
    func startOrSetUpEngine() {
        if !FileManager.default.isExecutableFile(atPath: preferences.python) { showingEngineSetup = true }
        else { restartEngine() }
    }
    func restartEngine() {
        guard activeTake == nil else { message = "Stop the queue before restarting the engine."; return }
        engine.start(python: preferences.python, device: preferences.device, modelFolder: preferences.modelFolder, log: logURL)
    }
    private func next() {
        guard queueRunning, activeTake == nil else { return }
        guard let take = library.takes.first(where: { $0.status == .queued }) else {
            queueRunning = false; progress = "Queue complete"; return
        }
        let config = "\(preferences.python)|\(take.device)|\(take.modelFolder)"
        if engine.configuration != config || (!engine.isReady && !engine.isStarting) {
            startingJob = take
            engine.start(python: preferences.python, device: take.device, modelFolder: take.modelFolder, log: logURL)
            return
        }
        guard engine.isReady else { return }
        activeTake = take.id; progress = "Preparing \(take.displayTitle)…"
        mutateTake(take.id) { $0.status = .running; $0.error = "" }
        do {
            if take.audioFile.hasPrefix("/") { try validateTakesFolder(take.audioURL(relativeTo: Store.root).deletingLastPathComponent()) }
            try engine.send(["command": "generate", "id": take.id.uuidString, "text": take.text,
                "speaker": take.speaker, "references": take.references.map { Store.root.appending(path: $0).path },
                "cached_voice": take.cachedVoice.map { Store.root.appending(path: $0).path } ?? "",
                "language": take.language, "speed": take.speed, "seed": take.seed,
                "output": take.audioURL(relativeTo: Store.root).path])
        } catch { handle(["event": "error", "id": take.id.uuidString, "message": error.localizedDescription]) }
    }
    private func handle(_ event: [String: Any]) {
        let type = event["event"] as? String ?? ""
        if type == "ready" { startingJob = nil; next(); return }
        if type == "engineError" {
            if let id = activeTake { mutateTake(id) { $0.status = .failed; $0.error = event["message"] as? String ?? "Engine stopped." } }
            activeTake = nil; queueRunning = false; startingJob = nil
            message = event["message"] as? String ?? "The speech engine stopped."
            return
        }
        guard let idString = event["id"] as? String, let id = UUID(uuidString: idString), id == activeTake else { return }
        switch type {
        case "progress": progress = event["message"] as? String ?? "Generating…"
        case "complete":
            mutateTake(id) { take in
                take.status = .completed
                take.duration = event["duration"] as? Double ?? 0
                take.generationSeconds = event["seconds"] as? Double ?? 0
            }
            selectedTake = id; completedInBatch += 1; activeTake = nil
            if preferences.autoplay, let take = library.takes.first(where: { $0.id == id }) { play(take) }
            next()
        case "error":
            mutateTake(id) { $0.status = .failed; $0.error = event["message"] as? String ?? "Generation failed." }
            activeTake = nil; completedInBatch += 1; next()
        default: break
        }
    }
    func mutateTake(_ id: UUID, _ change: (inout SpeechTake) -> Void) {
        guard let i = library.takes.firstIndex(where: { $0.id == id }) else { return }; change(&library.takes[i])
    }
    func stopQueue() {
        queueRunning = false; engine.stop(); activeTake = nil; startingJob = nil
        for i in library.takes.indices where [.queued, .running].contains(library.takes[i].status) {
            let take = library.takes[i]
            library.takes[i].status = .canceled
            try? FileManager.default.removeItem(at: take.audioURL(relativeTo: Store.root).deletingPathExtension().appendingPathExtension("partial.wav"))
        }
        progress = "Queue stopped"
    }
    func retryTakes(_ ids: Set<UUID>) {
        let sources = takes.filter { ids.contains($0.id) }
        for source in sources { retry(source) }
    }
    func retry(_ take: SpeechTake) {
        guard take.importedFilename == nil, ![.queued, .running].contains(take.status), prepareTakeStorage() else { return }
        // A retry is a new take. Original audio/metadata remain immutable for the future editor.
        let script = ScriptDocument(title: take.title, text: take.text)
        var copy = SpeechTake(script: script, voiceName: take.voiceName, speaker: take.speaker, references: take.references,
            language: take.language, speed: take.speed, seed: take.seed, modelFolder: take.modelFolder, device: take.device,
            number: (library.takes.filter { $0.scriptID == take.scriptID }.map(\.number).max() ?? 0) + 1, cachedVoice: take.cachedVoice)
        copy.scriptID = take.scriptID
        setOutputLocation(&copy)
        library.takes.append(copy); selectedTake = copy.id
        if queueRunning { batchTotal += 1 } else { resumeQueue() }
    }
    func removeTake(_ take: SpeechTake, undo: UndoManager?) {
        removeTakes([take.id], undo: undo)
    }
    func removeTakes(_ ids: Set<UUID>, undo: UndoManager?) {
        let removed = library.takes.enumerated().filter {
            ids.contains($0.element.id) && ![.queued, .running].contains($0.element.status)
        }
        guard !removed.isEmpty else { return }
        let removedIDs = Set(removed.map { $0.element.id })
        library.takes.removeAll { removedIDs.contains($0.id) }
        selectedTakes.subtract(removedIDs)
        undo?.registerUndo(withTarget: self) { model in
            for (index, take) in removed { model.library.takes.insert(take, at: min(index, model.library.takes.count)) }
            model.selectedTakes = removedIDs
        }
        undo?.setActionName("Remove Clips")
    }
    func play(_ take: SpeechTake) {
        do { try playback.toggle(take.audioURL(relativeTo: Store.root)) }
        catch { message = "Unable to play this clip: \(error.localizedDescription)" }
    }
    func export(_ take: SpeechTake) {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.wav]
        try? FileManager.default.createDirectory(at: exportFolder, withIntermediateDirectories: true)
        panel.directoryURL = exportFolder
        panel.nameFieldStringValue = "\(take.title.replacingOccurrences(of: "/", with: "-"))-clip-\(take.number).wav"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do { try copyTake(take, to: destination); preferences.exportFolder = destination.deletingLastPathComponent().path }
        catch { message = "Unable to export audio: \(error.localizedDescription)" }
    }
    func copyTake(_ take: SpeechTake, to destination: URL) throws {
        try Data(contentsOf: take.audioURL(relativeTo: Store.root)).write(to: destination, options: .atomic)
    }
    func reveal(_ take: SpeechTake) { NSWorkspace.shared.activateFileViewerSelecting([take.audioURL(relativeTo: Store.root)]) }
    func shutdown() {
        installer.cancel()
        queueRunning = false
        if let id = activeTake { mutateTake(id) { $0.status = .failed; $0.error = "Generation was interrupted when the app quit. Retry this clip." } }
        engine.stop(); playback.stop(); save()
    }
}

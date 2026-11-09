import AppKit
import UniformTypeIdentifiers
import VoiceStudioKit

extension UTType {
    static let voiceTimeline = UTType(exportedAs: "com.robschoen.voicestudio.timeline", conformingTo: .json)
}

extension AppModel {
    var exportFolder: URL {
        (preferences.exportFolder ?? preferences.takesFolder).map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? Store.root.appending(path: "Exports", directoryHint: .isDirectory)
    }
    func chooseExportFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Export Folder"; panel.canChooseDirectories = true
        panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.directoryURL = exportFolder
        if panel.runModal() == .OK, let url = panel.url { preferences.exportFolder = url.path }
    }
    func saveTimeline() {
        let panel = NSSavePanel()
        panel.title = "Save Timeline"; panel.allowedContentTypes = [.voiceTimeline]
        panel.nameFieldStringValue = "Timeline.vstimeline"
        try? FileManager.default.createDirectory(at: exportFolder, withIntermediateDirectories: true)
        panel.directoryURL = exportFolder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try saveTimeline(to: url)
            preferences.exportFolder = url.deletingLastPathComponent().path
        } catch { message = "Unable to save the timeline: \(error.localizedDescription)" }
    }
    func saveTimeline(to url: URL) throws {
        let sources = try Set(timeline.clips.map(\.takeID)).sorted { $0.uuidString < $1.uuidString }.map { id in
            guard let source = library.takes.first(where: { $0.id == id }),
                  let samples = samples(for: id), !samples.isEmpty else {
                throw LibraryFile.failure("A clip's source audio is missing. Restore it before saving.")
            }
            // Embed canonical WAV audio regardless of the original source format or location.
            let wav = FileManager.default.temporaryDirectory.appending(path: "VoiceStudio-save-\(UUID()).wav")
            defer { try? FileManager.default.removeItem(at: wav) }
            try TimelineAudio.writeWAV(samples, to: wav)
            return TimelineSource(metadata: source, audio: try Data(contentsOf: wav))
        }
        let document = TimelineDocument(timeline: timeline, sources: sources)
        try document.validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(document).write(to: url, options: .atomic)
    }
    func loadTimeline(undo: UndoManager?) {
        let panel = NSOpenPanel()
        panel.title = "Load Timeline"; panel.allowedContentTypes = [.voiceTimeline]
        panel.directoryURL = exportFolder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try loadTimeline(from: url, undo: undo)
            preferences.exportFolder = url.deletingLastPathComponent().path
        } catch { message = "Unable to load the timeline: \(error.localizedDescription)" }
    }
    func loadTimeline(from url: URL, undo: UndoManager?) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let document = try JSONDecoder().decode(TimelineDocument.self, from: Data(contentsOf: url))
        try document.validate()
        var restored = document.timeline
        var sources: [SpeechTake] = []
        var decoded: [UUID: [Float]] = [:]
        var created: [URL] = []
        do {
            for saved in document.sources {
                let oldID = saved.metadata.id
                var source = saved.metadata
                let originalPath = Store.root.appending(path: "Audio/\(oldID).wav")
                source.id = library.takes.contains(where: { $0.id == oldID }) || FileManager.default.fileExists(atPath: originalPath.path) ? UUID() : oldID
                source.status = .completed
                source.audioFile = "Audio/\(source.id).wav"
                let destination = source.audioURL(relativeTo: Store.root)
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try saved.audio.write(to: destination, options: .atomic)
                created.append(destination)
                let samples = try TimelineAudio.samples(destination)
                guard !samples.isEmpty else { throw LibraryFile.failure("A saved recording contains no audio.") }
                source.duration = Double(samples.count) / TimelineAudio.sampleRate
                // Reopening a local timeline should reuse its immutable source recordings.
                if let existing = library.takes.first(where: { $0.id == oldID }),
                   let original = try? TimelineAudio.samples(existing.audioURL(relativeTo: Store.root)),
                   original.count == samples.count,
                   zip(original, samples).allSatisfy({ abs($0 - $1) <= 1 / 32768.0 }) {
                    source = existing
                    try? FileManager.default.removeItem(at: destination)
                }
                for index in restored.clips.indices where restored.clips[index].takeID == oldID {
                    guard restored.clips[index].outPoint <= source.duration + 1 / TimelineAudio.sampleRate else {
                        throw LibraryFile.failure("A saved clip extends beyond its source recording.")
                    }
                    restored.clips[index].takeID = source.id
                }
                if !library.takes.contains(where: { $0.id == source.id }) { sources.append(source) }
                decoded[source.id] = samples
            }
        } catch {
            for file in created { try? FileManager.default.removeItem(at: file) }
            throw error
        }
        library.takes.append(contentsOf: sources)
        sampleCache.merge(decoded) { _, new in new }
        setTimeline(restored, action: "Load Timeline", undo: undo)
        selectedClip = nil
        seekTimeline(0)
        sidebar = .editor
    }
}

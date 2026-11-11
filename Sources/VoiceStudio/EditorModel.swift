import AppKit
import Foundation
import UniformTypeIdentifiers
import VoiceStudioKit

enum ExportFormat: String, CaseIterable {
    case wav, mp3
    var title: String { rawValue.uppercased() }
    var type: UTType { self == .wav ? .wav : .mp3 }
}

/// The editor: arranging takes on up to three tracks, previewing the mix, and exporting it.
extension AppModel {
    var timeline: Timeline { library.timeline }
    var editorTakes: [SpeechTake] { takes.filter { $0.status == .completed } }
    var clip: TimelineClip? { timeline.clips.first { $0.id == selectedClip } }
    var clips: [TimelineClip] { timeline.clips.filter { selectedClips.contains($0.id) } }
    var isPlayingTimeline: Bool { timelineRender != nil && playback.url == timelineRender }
    /// The playhead, following playback while the timeline plays.
    var timelineTime: Double { max(0, isPlayingTimeline ? playback.position + timelinePlaybackOrigin : playhead) }
    static let zoomRange = 10.0...400.0

    func takeFor(_ clip: TimelineClip) -> SpeechTake? { library.takes.first { $0.id == clip.takeID } }

    /// Replaces the arrangement as one undoable step.
    func setTimeline(_ new: Timeline, action: String, undo: UndoManager?) {
        let old = library.timeline
        guard old != new else { return }
        library.timeline = new
        timelineChanged()
        selectedClips.formIntersection(new.clips.map(\.id))
        undo?.registerUndo(withTarget: self) { model in model.setTimeline(old, action: action, undo: undo) }
        undo?.setActionName(action)
    }
    func editTimeline(_ action: String, undo: UndoManager?, _ change: (inout Timeline) -> Void) {
        var copy = library.timeline
        change(&copy)
        setTimeline(copy, action: action, undo: undo)
    }
    /// A rendered preview no longer matches the arrangement. Stop it so nothing stale plays.
    private func timelineChanged() {
        if isPlayingTimeline { playhead = timelineTime; playback.stop() }
        if let timelineRender { try? FileManager.default.removeItem(at: timelineRender) }
        timelineRender = nil
        loadWaveforms()
    }

    // MARK: Audio

    func samples(for takeID: UUID) -> [Float]? {
        if let cached = sampleCache[takeID] { return cached }
        guard let take = library.takes.first(where: { $0.id == takeID }), take.status == .completed,
              let samples = try? TimelineAudio.samples(take.audioURL(relativeTo: Store.root)) else { return nil }
        sampleCache[takeID] = samples
        return samples
    }
    /// The audible length of a take, from its decoded audio when available.
    func sourceDuration(_ takeID: UUID) -> Double {
        if let samples = samples(for: takeID) { return Double(samples.count) / TimelineAudio.sampleRate }
        return library.takes.first { $0.id == takeID }?.duration ?? 0
    }
    func loadWaveforms() {
        for id in Set(timeline.clips.map(\.takeID)) where waveforms[id] == nil {
            if let samples = samples(for: id) { waveforms[id] = TimelineAudio.peaks(samples) }
        }
    }
    func mixdown() -> [Float] { TimelineMixer.mix(timeline, sampleRate: TimelineAudio.sampleRate) { samples(for: $0) } }

    // MARK: Actions

    static let clipPasteboardType = "com.robschoen.voicestudio.timeline-clip"

    /// Shift adds clips to the selection; Command toggles an individual clip.
    func selectClip(_ id: UUID, modifiers: NSEvent.ModifierFlags = []) {
        if modifiers.contains(.command) {
            if selectedClips.contains(id) { selectedClips.remove(id) } else { selectedClips.insert(id) }
        } else if modifiers.contains(.shift) {
            selectedClips.insert(id)
        } else { selectedClips = [id] }
    }

    func copyClips() -> Data? {
        guard !clips.isEmpty else { return nil }
        return try? JSONEncoder().encode(clips)
    }

    func pasteClip(_ data: Data, undo: UndoManager?) {
        let decoder = JSONDecoder()
        // Also accept the single-clip clipboard used by older versions.
        guard var pasted = (try? decoder.decode([TimelineClip].self, from: data))
                ?? (try? decoder.decode(TimelineClip.self, from: data)).map({ [$0] }),
              !pasted.isEmpty, pasted.allSatisfy({ clip in
                  library.takes.contains { $0.id == clip.takeID } && timeline.tracks.indices.contains(clip.track)
                      && clip.start.isFinite && clip.start >= 0 && clip.inPoint.isFinite && clip.inPoint >= 0
                      && clip.outPoint.isFinite && clip.length >= Timeline.minimumLength
              }), let origin = pasted.map(\.start).min() else { return }
        let position = timelineTime
        for index in pasted.indices {
            pasted[index].id = UUID()
            pasted[index].start = position + pasted[index].start - origin
        }
        editTimeline("Paste Clips", undo: undo) { $0.clips.append(contentsOf: pasted) }
        selectedClips = Set(pasted.map(\.id))
    }

    /// Places all selected source clips sequentially, in their displayed list order.
    func addTakesToTimeline(_ ids: Set<UUID>, track: Int, undo: UndoManager?) {
        let sources = editorTakes.filter { ids.contains($0.id) }
        var next = timeline
        var added = Set<UUID>()
        for source in sources {
            let duration = sourceDuration(source.id)
            guard duration > 0 else { continue }
            added.insert(next.add(takeID: source.id, duration: duration, track: track).id)
        }
        guard !added.isEmpty else { return }
        setTimeline(next, action: "Add Clips", undo: undo)
        selectedClips = added
    }

    /// Imports a private copy so moving or deleting the original file cannot break the project.
    @discardableResult
    func importAudio(_ urls: [URL], track: Int = 0, at start: Double? = nil, undo: UndoManager?) -> Bool {
        var placed = false
        var position = start ?? timeline.end(of: track)
        for url in urls {
            guard ["wav", "mp3"].contains(url.pathExtension.lowercased()) else { continue }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                let samples = try TimelineAudio.samples(url)
                guard !samples.isEmpty else { throw LibraryFile.failure("This file contains no readable audio.") }
                var source = SpeechTake(script: ScriptDocument(title: url.deletingPathExtension().lastPathComponent),
                    voiceName: "Imported audio", speaker: "", references: [], language: "en", speed: 1,
                    seed: 0, modelFolder: "", device: "", number: 1)
                source.status = .completed; source.duration = Double(samples.count) / TimelineAudio.sampleRate
                source.modelName = "Imported audio"; source.importedFilename = url.lastPathComponent
                let destination = source.audioURL(relativeTo: Store.root)
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try TimelineAudio.writeWAV(samples, to: destination)
                library.takes.append(source)
                sampleCache[source.id] = samples
                addToTimeline(source, track: track, at: position, undo: undo)
                position += source.duration
                selectedTake = source.id; placed = true
            } catch { message = "Unable to import \(url.lastPathComponent): \(error.localizedDescription)" }
        }
        return placed
    }

    func importAudio(undo: UndoManager?) {
        let panel = NSOpenPanel()
        panel.title = "Import Audio Clips"; panel.allowedContentTypes = [.wav, .mp3]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        _ = importAudio(panel.urls, undo: undo)
    }

    func addToTimeline(_ take: SpeechTake, track: Int, at start: Double? = nil, undo: UndoManager?) {
        guard take.status == .completed else { return }
        let length = sourceDuration(take.id)
        guard length > 0 else { message = "This clip's audio could not be read. Generate it again."; return }
        var added: TimelineClip?
        editTimeline("Add Clip", undo: undo) { added = $0.add(takeID: take.id, duration: length, track: track, at: start) }
        selectedClip = added?.id
    }
    func splitAtPlayhead(undo: UndoManager?) {
        let time = timelineTime
        let ids = selectedClips
        if ids.isEmpty {
            editTimeline("Split Clips", undo: undo) { $0.splitAll(at: time) }
        } else {
            editTimeline("Split Clips", undo: undo) { timeline in
                for id in ids { timeline.split(id, at: time) }
            }
        }
    }
    func deleteClip(ripple: Bool, undo: UndoManager?) {
        let ids = selectedClips
        guard !ids.isEmpty else { return }
        editTimeline(ripple ? "Ripple Delete" : "Delete Clips", undo: undo) { ripple ? $0.rippleRemove(ids) : $0.remove(ids) }
    }
    func clearTimeline(undo: UndoManager?) {
        editTimeline("Clear Timeline", undo: undo) { $0.clips.removeAll(); $0.loop = nil }
        seekTimeline(0)
    }
    func setTrack(_ index: Int, muted: Bool? = nil, volume: Double? = nil, undo: UndoManager?) {
        editTimeline(muted != nil ? (muted! ? "Mute Track" : "Unmute Track") : "Change Volume", undo: undo) {
            if let muted { $0.tracks[index].muted = muted }
            if let volume { $0.tracks[index].volume = volume }
        }
    }
    func seekTimeline(_ time: Double, reveal: Bool = true) {
        playhead = max(0, time)
        if isPlayingTimeline {
            let local = playhead - timelinePlaybackOrigin
            if local < 0 || local > playback.duration { playback.stop() }
            else { playback.seek(local) }
        }
        if reveal { timelineRevealRequest = UUID() }
    }
    func zoom(by factor: Double) { zoom = min(max(zoom * factor, Self.zoomRange.lowerBound), Self.zoomRange.upperBound) }

    var timelineLoopEnabled: Bool { timeline.loop?.enabled == true }
    func setTimelineLoopEnabled(_ enabled: Bool, undo: UndoManager?) {
        guard enabled != timelineLoopEnabled, let range = timeline.loopRange else { return }
        let resume = isPlayingTimeline && playback.isPlaying
        editTimeline("Change Loop", undo: undo) {
            $0.loop = TimelineLoop(start: range.lowerBound, end: range.upperBound, enabled: enabled)
        }
        if resume { toggleTimelinePlayback() }
    }
    func setLoopMarker(start: Bool, time: Double, undo: UndoManager?) {
        guard timeline.loopRange != nil else { return }
        editTimeline("Move Loop Marker", undo: undo) { $0.setLoopMarker(start: start, time: time) }
    }

    func toggleTimelinePlayback() {
        guard !timeline.isEmpty else { return }
        if isPlayingTimeline {
            if playback.isPlaying { playhead = timelineTime; playback.toggle() }
            else {
                let local = playhead - timelinePlaybackOrigin
                playback.seek(local >= 0 && local < playback.duration ? local : 0)
                playback.toggle()
            }
            return
        }
        do {
            var samples = mixdown()
            timelinePlaybackOrigin = 0
            if timelineLoopEnabled, let range = timeline.loopRange {
                let first = Int((range.lowerBound * TimelineAudio.sampleRate).rounded())
                let last = min(samples.count, Int((range.upperBound * TimelineAudio.sampleRate).rounded()))
                samples = Array(samples[first..<last])
                timelinePlaybackOrigin = Double(first) / TimelineAudio.sampleRate
            }
            let url = FileManager.default.temporaryDirectory.appending(path: "VoiceStudio-timeline-\(UUID().uuidString).wav")
            try TimelineAudio.writeWAV(samples, to: url)
            if let old = timelineRender { try? FileManager.default.removeItem(at: old) }
            timelineRender = url
            playback.loops = timelineLoopEnabled
            let local = playhead - timelinePlaybackOrigin
            let duration = Double(samples.count) / TimelineAudio.sampleRate
            try playback.start(url, at: local >= 0 && local < duration ? local : 0)
            timelineRevealRequest = UUID()
        } catch { message = "Unable to play the timeline: \(error.localizedDescription)" }
    }

    func exportTimeline(_ format: ExportFormat) {
        guard !timeline.isEmpty else { return }
        let panel = NSSavePanel()
        panel.title = "Export Timeline as \(format.title)"
        panel.allowedContentTypes = [format.type]
        try? FileManager.default.createDirectory(at: exportFolder, withIntermediateDirectories: true)
        panel.directoryURL = exportFolder
        panel.nameFieldStringValue = "Timeline.\(format.rawValue)"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do { try exportTimeline(format, to: destination); preferences.exportFolder = destination.deletingLastPathComponent().path }
        catch { message = "Unable to export the timeline: \(error.localizedDescription)" }
    }
    func exportTimeline(_ format: ExportFormat, to destination: URL) throws {
        guard timeline.clips.contains(where: { !timeline.tracks[$0.track].muted && $0.length > 0 }) else {
            throw LibraryFile.failure("Every track with clips is muted. Unmute a track to export it.")
        }
        let samples = mixdown()
        switch format {
        case .wav: try TimelineAudio.writeWAV(samples, to: destination)
        case .mp3:
            let wav = FileManager.default.temporaryDirectory.appending(path: "VoiceStudio-export-\(UUID().uuidString).wav")
            defer { try? FileManager.default.removeItem(at: wav) }
            try TimelineAudio.writeWAV(samples, to: wav)
            try TimelineAudio.encodeMP3(wav: wav, to: destination)
        }
    }
}

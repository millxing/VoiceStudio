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
    var isPlayingTimeline: Bool { timelineRender != nil && playback.url == timelineRender }
    /// The playhead, following playback while the timeline plays.
    var timelineTime: Double { isPlayingTimeline ? playback.position : playhead }
    static let zoomRange = 10.0...400.0

    func takeFor(_ clip: TimelineClip) -> SpeechTake? { library.takes.first { $0.id == clip.takeID } }

    /// Replaces the arrangement as one undoable step.
    func setTimeline(_ new: Timeline, action: String, undo: UndoManager?) {
        let old = library.timeline
        guard old != new else { return }
        library.timeline = new
        timelineChanged()
        if let selectedClip, !new.clips.contains(where: { $0.id == selectedClip }) { self.selectedClip = nil }
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
        if isPlayingTimeline { playhead = playback.position; playback.stop() }
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

    func addToTimeline(_ take: SpeechTake, track: Int, at start: Double? = nil, undo: UndoManager?) {
        guard take.status == .completed else { return }
        let length = sourceDuration(take.id)
        guard length > 0 else { message = "This take's audio could not be read. Generate it again."; return }
        var added: TimelineClip?
        editTimeline("Add Clip", undo: undo) { added = $0.add(takeID: take.id, duration: length, track: track, at: start) }
        selectedClip = added?.id
    }
    func splitAtPlayhead(undo: UndoManager?) {
        let time = timelineTime
        // With a clip selected, split only that clip; otherwise split everything under the playhead.
        if let clip, clip.start < time, clip.end > time {
            editTimeline("Split Clip", undo: undo) { $0.split(clip.id, at: time) }
        } else {
            editTimeline("Split Clips", undo: undo) { $0.splitAll(at: time) }
        }
    }
    func deleteClip(ripple: Bool, undo: UndoManager?) {
        guard let id = selectedClip else { return }
        editTimeline(ripple ? "Ripple Delete" : "Delete Clip", undo: undo) { ripple ? $0.rippleRemove([id]) : $0.remove([id]) }
    }
    func clearTimeline(undo: UndoManager?) {
        editTimeline("Clear Timeline", undo: undo) { $0.clips.removeAll() }
        playhead = 0
    }
    func setTrack(_ index: Int, muted: Bool? = nil, volume: Double? = nil, undo: UndoManager?) {
        editTimeline(muted != nil ? (muted! ? "Mute Track" : "Unmute Track") : "Change Volume", undo: undo) {
            if let muted { $0.tracks[index].muted = muted }
            if let volume { $0.tracks[index].volume = volume }
        }
    }
    func seekTimeline(_ time: Double) {
        playhead = max(0, time)
        if isPlayingTimeline { playback.seek(min(playhead, playback.duration)) }
    }
    func zoom(by factor: Double) { zoom = min(max(zoom * factor, Self.zoomRange.lowerBound), Self.zoomRange.upperBound) }

    func toggleTimelinePlayback() {
        guard !timeline.isEmpty else { return }
        if isPlayingTimeline {
            if playback.isPlaying { playback.toggle(); playhead = playback.position }
            else { playback.seek(playhead); playback.toggle() }
            return
        }
        do {
            let url = FileManager.default.temporaryDirectory.appending(path: "VoiceStudio-timeline-\(UUID().uuidString).wav")
            try TimelineAudio.writeWAV(mixdown(), to: url)
            timelineRender = url
            try playback.start(url, at: playhead >= timeline.duration ? 0 : playhead)
        } catch { message = "Unable to play the timeline: \(error.localizedDescription)" }
    }

    func exportTimeline(_ format: ExportFormat) {
        guard !timeline.isEmpty else { return }
        let panel = NSSavePanel()
        panel.title = "Export Timeline as \(format.title)"
        panel.allowedContentTypes = [format.type]
        panel.nameFieldStringValue = "Timeline.\(format.rawValue)"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do { try exportTimeline(format, to: destination) }
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

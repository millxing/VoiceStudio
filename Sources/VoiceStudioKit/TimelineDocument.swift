import Foundation

/// A portable timeline: each distinct source recording is embedded once.
public struct TimelineSource: Codable, Sendable {
    public var metadata: SpeechTake
    public var audio: Data
    public init(metadata: SpeechTake, audio: Data) { self.metadata = metadata; self.audio = audio }
}
public struct TimelineDocument: Codable, Sendable {
    public var version = 1
    public var timeline: Timeline
    public var sources: [TimelineSource]
    public init(timeline: Timeline, sources: [TimelineSource]) { self.timeline = timeline; self.sources = sources }
    public func validate() throws {
        guard version == 1 else { throw LibraryFile.failure("This timeline needs a newer version of VoiceStudio.") }
        let sourceIDs = Set(sources.map { $0.metadata.id })
        guard sourceIDs.count == sources.count,
              Set(timeline.clips.map(\.id)).count == timeline.clips.count,
              timeline.tracks.count == Timeline.trackCount,
              timeline.tracks.allSatisfy({ $0.volume.isFinite && (0...2).contains($0.volume) }),
              timeline.clips.allSatisfy({
                  sourceIDs.contains($0.takeID) && (0..<Timeline.trackCount).contains($0.track)
                    && $0.start.isFinite && $0.start >= 0 && $0.inPoint.isFinite && $0.inPoint >= 0
                    && $0.outPoint.isFinite && $0.length >= Timeline.minimumLength
              }), sources.allSatisfy({ !$0.audio.isEmpty }) else {
            throw LibraryFile.failure("This timeline contains invalid clips, tracks, or missing audio.")
        }
        if let loop = timeline.loop {
            guard loop.start.isFinite, loop.end.isFinite, loop.start >= 0, loop.end > loop.start else {
                throw LibraryFile.failure("This timeline contains invalid loop markers.")
            }
        }
    }
}

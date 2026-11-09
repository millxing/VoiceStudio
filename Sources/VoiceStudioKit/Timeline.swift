import Foundation

/// One placed piece of a take on the editor timeline. Times are seconds.
/// `inPoint`/`outPoint` select the part of the take's audio that plays;
/// `start` is where that part begins on the timeline.
public struct TimelineClip: Identifiable, Codable, Hashable, Sendable {
    public var id = UUID()
    public var takeID: UUID
    public var track: Int
    public var start: Double
    public var inPoint: Double
    public var outPoint: Double
    public var length: Double { outPoint - inPoint }
    public var end: Double { start + length }
    public init(takeID: UUID, track: Int, start: Double, inPoint: Double = 0, outPoint: Double) {
        self.takeID = takeID; self.track = track; self.start = start; self.inPoint = inPoint; self.outPoint = outPoint
    }
}

public struct TimelineTrack: Codable, Hashable, Sendable {
    public var muted = false
    /// Linear gain, 0...2.
    public var volume = 1.0
    public init() {}
}

/// The editor's arrangement: up to three tracks of clips that mix down on export.
public struct Timeline: Codable, Equatable, Sendable {
    public static let trackCount = 3
    /// Shortest clip a trim or split may leave behind.
    public static let minimumLength = 0.05
    public var clips: [TimelineClip] = []
    public var tracks = Array(repeating: TimelineTrack(), count: Timeline.trackCount)
    public init() {}

    public var duration: Double { clips.map(\.end).max() ?? 0 }
    public var isEmpty: Bool { clips.isEmpty }
    public func clips(on track: Int) -> [TimelineClip] { clips.filter { $0.track == track }.sorted { $0.start < $1.start } }
    public func end(of track: Int) -> Double { clips(on: track).map(\.end).max() ?? 0 }

    @discardableResult
    public mutating func add(takeID: UUID, duration: Double, track: Int, at start: Double? = nil) -> TimelineClip {
        let clip = TimelineClip(takeID: takeID, track: Self.clampTrack(track), start: max(0, start ?? end(of: track)), outPoint: max(Self.minimumLength, duration))
        clips.append(clip)
        return clip
    }
    public mutating func move(_ id: UUID, to start: Double, track: Int) {
        guard let i = clips.firstIndex(where: { $0.id == id }) else { return }
        clips[i].start = max(0, start); clips[i].track = Self.clampTrack(track)
    }
    /// Moves the clip's left edge to `time` on the timeline, keeping the audio under the rest of the clip in place.
    public mutating func trimStart(_ id: UUID, to time: Double) {
        guard let i = clips.firstIndex(where: { $0.id == id }) else { return }
        let c = clips[i]
        // The left edge cannot pass the take's first sample or the timeline's zero.
        let lowest = max(0, c.inPoint - c.start)
        let newIn = min(max(lowest, c.inPoint + (time - c.start)), c.outPoint - Self.minimumLength)
        clips[i].start = c.start + (newIn - c.inPoint)
        clips[i].inPoint = newIn
    }
    /// Moves the clip's right edge to `time` on the timeline, limited by the take's audio length.
    public mutating func trimEnd(_ id: UUID, to time: Double, sourceDuration: Double) {
        guard let i = clips.firstIndex(where: { $0.id == id }) else { return }
        let c = clips[i]
        clips[i].outPoint = min(max(c.inPoint + Self.minimumLength, c.inPoint + (time - c.start)), max(sourceDuration, c.inPoint + Self.minimumLength))
    }
    /// Splits the clip at a timeline time. Returns the id of the new right half.
    @discardableResult
    public mutating func split(_ id: UUID, at time: Double) -> UUID? {
        guard let i = clips.firstIndex(where: { $0.id == id }) else { return nil }
        let c = clips[i]
        guard time - c.start >= Self.minimumLength, c.end - time >= Self.minimumLength else { return nil }
        let cut = c.inPoint + (time - c.start)
        clips[i].outPoint = cut
        var right = c; right.id = UUID(); right.start = time; right.inPoint = cut
        clips.insert(right, at: i + 1)
        return right.id
    }
    /// Splits every clip under the playhead (or only those on `track`).
    @discardableResult
    public mutating func splitAll(at time: Double, track: Int? = nil) -> [UUID] {
        clips.filter { $0.start < time && $0.end > time && (track == nil || $0.track == track) }.compactMap { split($0.id, at: time) }
    }
    public mutating func remove(_ ids: Set<UUID>) { clips.removeAll { ids.contains($0.id) } }
    /// Removes clips and closes the gap they leave on their track.
    public mutating func rippleRemove(_ ids: Set<UUID>) {
        let removed = clips.filter { ids.contains($0.id) }.sorted { $0.start > $1.start }
        remove(ids)
        for gone in removed {
            for i in clips.indices where clips[i].track == gone.track && clips[i].start >= gone.start {
                clips[i].start = max(0, clips[i].start - gone.length)
            }
        }
    }
    /// Snaps a proposed clip start so its start or end meets a nearby edge (other clips, zero, the playhead).
    public func snap(start: Double, length: Double, excluding id: UUID?, extra: [Double] = [], tolerance: Double) -> Double {
        var edges = [0.0] + extra
        for c in clips where c.id != id { edges += [c.start, c.end] }
        var best = start, distance = tolerance
        for edge in edges {
            if abs(edge - start) < distance { distance = abs(edge - start); best = edge }
            if abs(edge - (start + length)) < distance { distance = abs(edge - (start + length)); best = edge - length }
        }
        return max(0, best)
    }
    /// Snaps a single time (a trim edge or the playhead) to the nearest clip edge.
    public func snap(time: Double, excluding id: UUID?, extra: [Double] = [], tolerance: Double) -> Double {
        snap(start: time, length: 0, excluding: id, extra: extra, tolerance: tolerance)
    }
    static func clampTrack(_ track: Int) -> Int { min(max(0, track), trackCount - 1) }
}

public enum TimelineMixer {
    /// Mixes clips into one mono signal. `source` returns a take's samples at `sampleRate`.
    /// Each clip gets short fades so cuts do not click. Peaks above full scale are scaled down.
    public static func mix(_ timeline: Timeline, sampleRate: Double, fade: Double = 0.005, source: (UUID) -> [Float]?) -> [Float] {
        let total = Int((timeline.duration * sampleRate).rounded(.up))
        guard total > 0 else { return [] }
        var out = [Float](repeating: 0, count: total)
        for clip in timeline.clips {
            let track = timeline.tracks.indices.contains(clip.track) ? timeline.tracks[clip.track] : TimelineTrack()
            guard !track.muted, track.volume > 0, let samples = source(clip.takeID) else { continue }
            let from = max(0, Int((clip.inPoint * sampleRate).rounded()))
            let to = min(samples.count, Int((clip.outPoint * sampleRate).rounded()))
            guard to > from else { continue }
            let offset = Int((clip.start * sampleRate).rounded())
            let count = to - from
            let fadeFrames = max(1, min(count / 2, Int(fade * sampleRate)))
            let gain = Float(track.volume)
            for n in 0..<count {
                let target = offset + n
                guard target < total else { break }
                var g = gain
                if n < fadeFrames { g *= Float(n) / Float(fadeFrames) }
                if count - n <= fadeFrames { g *= Float(count - n - 1) / Float(fadeFrames) }
                out[target] += samples[from + n] * g
            }
        }
        let peak = out.reduce(0) { max($0, abs($1)) }
        if peak > 0.99 { let scale = 0.99 / peak; for i in out.indices { out[i] *= scale } }
        return out
    }
}

import SwiftUI
import UniformTypeIdentifiers
import VoiceStudioKit

/// Editor sizes. Lanes are tall enough for a readable waveform under the clip title.
enum EditorMetrics {
    static let loopHeight: CGFloat = 20
    static let ruler: CGFloat = 48
    static let lane: CGFloat = 88
    static let headerWidth: CGFloat = 168
    static let handle: CGFloat = 8
    static let clipInset: CGFloat = 4
    static let clipRadius: CGFloat = 4
    /// How close, in points, an edge must come to another edge to snap to it.
    static let snap: CGFloat = 8
    /// Empty timeline after the last clip, in seconds, so there is room to drop.
    static let tail = 10.0
    static var height: CGFloat { ruler + lane * CGFloat(Timeline.trackCount) }
}

/// Where the timeline canvas sits in its window (top-left origin), so the self-test can aim mouse events at clips.
enum EditorProbe {
    static var canvas: CGRect = .zero
    static var viewport: CGRect = .zero
    static var playhead: CGRect = .zero
    static weak var scrollView: NSScrollView?
}

/// The content column: completed takes, ready to drag onto the timeline.
struct EditorBin: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undo
    var body: some View {
        @Bindable var model = model
        List(model.editorTakes, selection: $model.selectedTakes) { take in
            HStack(spacing: Space.sm) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(take.displayTitle).lineLimit(1).help(take.displayTitle)
                    Text("\(take.voiceName) · \(timeLabel(take.duration))").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: Space.sm)
                let playing = model.playback.url == take.audioURL(relativeTo: Store.root) && model.playback.isPlaying
                Button(playing ? "Pause" : "Play", systemImage: playing ? "pause.fill" : "play.fill") { model.play(take) }
                    .labelStyle(.iconOnly).buttonStyle(.borderless).help("Preview this clip")
            }
            .padding(.vertical, Space.xs).tag(take.id)
            .draggable(take.id.uuidString)
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            ForEach(0..<Timeline.trackCount, id: \.self) { track in
                Button("Add Selected Clips to Track \(track + 1)") { model.addTakesToTimeline(ids, track: track, undo: undo) }
                    .disabled(ids.isEmpty)
            }
            Divider()
            Button("Generate Selected Again") { model.retryTakes(ids) }.disabled(!model.editorTakes.contains { ids.contains($0.id) && $0.importedFilename == nil })
            Button("Remove Selected Clips", role: .destructive) { model.removeTakes(ids, undo: undo) }
                .disabled(ids.isEmpty)
        }
        .onDeleteCommand { model.removeTakes(model.selectedTakes, undo: undo) }

        .overlay {
            if model.editorTakes.isEmpty {
                ContentUnavailableView("No Clips to Edit", systemImage: "waveform",
                    description: Text("Generate clips from Scripts or drop WAV/MP3 files here."))
            }
        }
        .dropDestination(for: URL.self) { urls, _ in model.importAudio(urls, undo: undo) }
        .navigationTitle("Editor")
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 400)
        .toolbar {
            ToolbarItem {
                Button("Add to Timeline", systemImage: "plus.rectangle.on.rectangle") {
                    model.addTakesToTimeline(model.selectedTakes, track: 0, undo: undo)
                }
                .disabled(!model.editorTakes.contains { model.selectedTakes.contains($0.id) })
                .help("Add the selected clips to the end of track 1 (Shift-Command-A)")
            }
        }
    }
}

/// The detail column: transport, three tracks, and the selected clip.
struct EditorDetail: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undo
    /// The arrangement while a drag or slider is in progress. Committed once, as one undo step, when it ends.
    @State private var draft: Timeline?
    @State private var dragBase: Timeline?
    @State private var dragDuplicate: UUID?
    @State private var dragSelection = Set<UUID>()
    @State private var dragCopies: [UUID: UUID] = [:]
    @State private var focusRequest: UUID?
    @State private var scrollPosition = ScrollPosition(x: 0)

    var body: some View {
        let shown = draft ?? model.timeline
        VStack(spacing: 0) {
            EditorTransport()
                .padding(.horizontal, Space.margin).padding(.vertical, Space.md)
            Divider()
            HStack(alignment: .top, spacing: 0) {
                trackHeaders(shown)
                Divider()
                GeometryReader { geometry in
                    ScrollView(.horizontal) {
                        canvas(shown)
                            .frame(width: max(geometry.size.width, (shown.duration + EditorMetrics.tail) * model.zoom),
                                   height: EditorMetrics.height, alignment: .topLeading)
                            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { EditorProbe.canvas = $0 }
                            .background(TimelineScrollProbe())
                    }
                    .scrollPosition($scrollPosition)
                    .onChange(of: model.timelineRevealRequest) {
                        scrollPosition.scrollTo(x: max(0, model.timelineTime * model.zoom - geometry.size.width / 4))
                    }
                    .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { EditorProbe.viewport = $0 }
                }
            }
            .frame(height: EditorMetrics.height)
            .background(TimelineKeyboard(model: model, focusRequest: focusRequest))
            Divider()
            inspector(shown)
                .padding(Space.margin).gridArea("editor-inspector", inset: 0)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
        .task(id: model.timeline.clips.map(\.takeID)) { model.loadWaveforms() }
    }

    // MARK: Track headers

    private func trackHeaders(_ shown: Timeline) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: EditorMetrics.ruler)
            ForEach(0..<Timeline.trackCount, id: \.self) { index in
                let track = shown.tracks[index]
                VStack(alignment: .leading, spacing: Space.xs) {
                    HStack(spacing: Space.sm) {
                        Text("Track \(index + 1)").font(.headline)
                        Spacer(minLength: Space.xs)
                        Toggle("Mute", systemImage: track.muted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                               isOn: Binding(get: { track.muted }, set: { model.setTrack(index, muted: $0, undo: undo) }))
                            .toggleStyle(.button).labelStyle(.iconOnly)
                            .help(track.muted ? "Unmute track \(index + 1)" : "Mute track \(index + 1)")
                    }
                    Slider(value: Binding(get: { track.volume }, set: { value in
                        var next = draft ?? model.timeline
                        next.tracks[index].volume = value
                        draft = next
                    }), in: 0...2) { editing in
                        if !editing, let draft { model.setTimeline(draft, action: "Change Volume", undo: undo); self.draft = nil }
                    }
                    .controlSize(.small)
                    .accessibilityLabel("Track \(index + 1) volume")
                    .help("Volume \(Int((track.volume * 100).rounded()))%")
                    Text("\(Int((track.volume * 100).rounded()))%").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
                .padding(.horizontal, Space.md)
                .frame(height: EditorMetrics.lane)
                .opacity(track.muted ? 0.6 : 1)
                .overlay(alignment: .bottom) { Divider() }
            }
        }
        .frame(width: EditorMetrics.headerWidth)
    }

    // MARK: Timeline

    private func canvas(_ shown: Timeline) -> some View {
        let pps = model.zoom
        return ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                TimelineRuler(pixelsPerSecond: pps)
                    .frame(height: EditorMetrics.ruler - EditorMetrics.loopHeight)
                    .padding(.top, EditorMetrics.loopHeight)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        focusRequest = UUID()
                        model.seekTimeline(value.location.x / pps, reveal: false)
                    })
                    .overlay(alignment: .bottom) { Divider() }
                ForEach(0..<Timeline.trackCount, id: \.self) { index in
                    Rectangle()
                        .fill(index.isMultiple(of: 2) ? AnyShapeStyle(.background) : AnyShapeStyle(.quinary))
                        .frame(height: EditorMetrics.lane)
                        .overlay(alignment: .bottom) { Divider() }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                focusRequest = UUID()
                model.selectedClip = nil
                model.seekTimeline(location.x / pps, reveal: false)
            }
            if shown.isEmpty {
                ContentUnavailableView("Drag Clips Here", systemImage: "square.and.arrow.down",
                    description: Text("Drop clips from the list or WAV/MP3 files onto any of the three tracks. Export mixes all tracks together."))
                    .frame(maxWidth: .infinity).frame(height: EditorMetrics.lane * CGFloat(Timeline.trackCount))
                    .offset(y: EditorMetrics.ruler) // grid: ok timeline coordinates
                    .allowsHitTesting(false)
            }
            ForEach(shown.clips) { clip in
                clipView(clip, pps: pps)
                    .frame(width: max(EditorMetrics.handle * 2, clip.length * pps),
                           height: EditorMetrics.lane - EditorMetrics.clipInset * 2)
                    .offset(x: clip.start * pps, // grid: ok timeline time-to-x placement
                            y: EditorMetrics.ruler + CGFloat(clip.track) * EditorMetrics.lane + EditorMetrics.clipInset) // grid: ok timeline coordinates
            }
            loopMarkers(shown, pps: pps)
            Playhead(pixelsPerSecond: pps)
            // A visible grab handle uses the canvas coordinates, even when scrolled.
            Image(systemName: "arrowtriangle.down.fill")
                .foregroundStyle(Palette.accent)
                .frame(width: 16, height: EditorMetrics.ruler - EditorMetrics.loopHeight)
                .contentShape(Rectangle())
                .offset(x: max(0, model.timelineTime * pps - 8), y: EditorMetrics.loopHeight) // grid: ok timeline time-to-x placement
                .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("timeline"))
                    .onChanged { value in focusRequest = UUID(); model.seekTimeline(value.location.x / pps, reveal: false) })
                .help("Drag to scrub the timeline")
                .accessibilityLabel("Playhead")
        }
        .coordinateSpace(.named("timeline"))
        .onDrop(of: [.fileURL, .utf8PlainText], isTargeted: nil) { providers, location in
            guard location.y >= EditorMetrics.ruler else { return false }
            let track = min(Timeline.trackCount - 1, Int((location.y - EditorMetrics.ruler) / EditorMetrics.lane))
            let start = model.timeline.snap(time: location.x / pps, excluding: nil,
                extra: [model.timelineTime], tolerance: EditorMetrics.snap / pps)
            let files = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
            if !files.isEmpty {
                // Load sequentially to preserve the order of multiple dropped files.
                Task { @MainActor in
                    var urls: [URL] = []
                    for provider in files {
                        let url: URL? = await withCheckedContinuation { continuation in
                            _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
                        }
                        if let url { urls.append(url) }
                    }
                    if model.importAudio(urls, track: track, at: start, undo: undo) { focusRequest = UUID() }
                }
                return true
            }
            let sources = providers.filter { $0.canLoadObject(ofClass: String.self) }
            Task { @MainActor in
                var position = start
                for provider in sources {
                    let item: String? = await withCheckedContinuation { continuation in
                        _ = provider.loadObject(ofClass: String.self) { item, _ in continuation.resume(returning: item) }
                    }
                    guard let item, let id = UUID(uuidString: item),
                          let source = model.library.takes.first(where: { $0.id == id }) else { continue }
                    model.addToTimeline(source, track: track, at: position, undo: undo)
                    position += model.sourceDuration(id)
                    focusRequest = UUID()
                }
            }
            return !sources.isEmpty
        }
    }

    @ViewBuilder private func loopMarkers(_ shown: Timeline, pps: Double) -> some View {
        if let range = shown.loopRange {
            Rectangle().fill(Palette.accent.opacity(shown.loop?.enabled == true ? 0.25 : 0.08))
                .frame(width: (range.upperBound - range.lowerBound) * pps, height: EditorMetrics.loopHeight)
                .overlay {
                    if (range.upperBound - range.lowerBound) * pps >= 64 {
                        Text("Loop").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .offset(x: range.lowerBound * pps) // grid: ok timeline time-to-x placement
                .allowsHitTesting(false)
            ForEach([true, false], id: \.self) { leading in
                let time = leading ? range.lowerBound : range.upperBound
                Image(systemName: leading ? "arrowtriangle.right.fill" : "arrowtriangle.left.fill")
                    .font(.caption).foregroundStyle(Palette.accent)
                    .frame(width: 16, height: EditorMetrics.loopHeight)
                    .background(.regularMaterial)
                    .contentShape(Rectangle()).pointerStyle(.columnResize)
                    .offset(x: max(0, time * pps - 8)) // grid: ok timeline time-to-x placement
                    .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("timeline"))
                        .onChanged { value in
                            if dragBase == nil { dragBase = model.timeline; focusRequest = UUID() }
                            var next = dragBase ?? model.timeline
                            next.setLoopMarker(start: leading, time: value.location.x / pps)
                            draft = next
                        }
                        .onEnded { _ in
                            let resume = model.isPlayingTimeline && model.playback.isPlaying
                            commit("Move Loop Marker")
                            if resume { model.toggleTimelinePlayback() }
                        })
                    .help(leading ? "Drag the loop start marker" : "Drag the loop end marker")
                    .accessibilityLabel(leading ? "Loop start" : "Loop end")
            }
        }
    }

    private func clipView(_ clip: TimelineClip, pps: Double) -> some View {
        ClipView(clip: clip, take: model.takeFor(clip), peaks: model.waveforms[clip.takeID],
                 selected: model.selectedClips.contains(clip.id), pixelsPerSecond: pps,
                 muted: model.timeline.tracks[clip.track].muted)
            .overlay(alignment: .leading) { trimHandle(clip, leading: true, pps: pps) }
            .overlay(alignment: .trailing) { trimHandle(clip, leading: false, pps: pps) }
            .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .named("timeline"))
                .onChanged { value in
                    guard let (base, original) = begin(clip, duplicate: (NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags).contains(.option)) else { return }
                    let originals = base.clips.filter { dragSelection.contains($0.id) }
                    let tracks = Int((value.translation.height / EditorMetrics.lane).rounded())
                    var snapBase = base
                    snapBase.clips.removeAll { dragSelection.contains($0.id) }
                    let start = snapBase.snap(start: original.start + value.translation.width / pps, length: original.length,
                                              excluding: nil, extra: [model.timelineTime], tolerance: EditorMetrics.snap / pps)
                    let delta = max(start - original.start, -(originals.map(\.start).min() ?? 0))
                    let trackDelta = min(max(tracks, -(originals.map(\.track).min() ?? 0)),
                                         Timeline.trackCount - 1 - (originals.map(\.track).max() ?? 0))
                    var next = base
                    for source in originals {
                        let id = dragCopies[source.id] ?? source.id
                        if dragCopies[source.id] != nil {
                            var copy = source; copy.id = id; next.clips.append(copy)
                        }
                        next.move(id, to: source.start + delta, track: source.track + trackDelta)
                    }
                    draft = next
                }
                .onEnded { _ in commit(dragDuplicate == nil ? "Move Clip" : "Duplicate Clip") })
            .onTapGesture {
                focusRequest = UUID()
                model.selectClip(clip.id, modifiers: NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(model.takeFor(clip)?.displayTitle ?? "Missing clip"), track \(clip.track + 1), starts \(preciseTimeLabel(clip.start))")
            .accessibilityAddTraits(model.selectedClips.contains(clip.id) ? .isSelected : [])
    }

    private func trimHandle(_ clip: TimelineClip, leading: Bool, pps: Double) -> some View {
        Rectangle().fill(.clear)
            .frame(width: EditorMetrics.handle)
            .contentShape(Rectangle())
            .pointerStyle(.columnResize)
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("timeline"))
                .onChanged { value in
                    guard let (base, original) = begin(clip) else { return }
                    let edge = (leading ? original.start : original.end) + value.translation.width / pps
                    let time = base.snap(time: edge, excluding: clip.id, extra: [model.timelineTime], tolerance: EditorMetrics.snap / pps)
                    var next = base
                    if leading { next.trimStart(clip.id, to: time) }
                    else { next.trimEnd(clip.id, to: time, sourceDuration: model.sourceDuration(clip.takeID)) }
                    draft = next
                }
                .onEnded { _ in commit("Trim Clip") })
            .help(leading ? "Drag to trim the start" : "Drag to trim the end")
    }

    /// The arrangement and clip as they were when the current drag began.
    private func begin(_ clip: TimelineClip, duplicate: Bool = false) -> (Timeline, TimelineClip)? {
        if dragBase == nil {
            dragBase = model.timeline
            if !model.selectedClips.contains(clip.id) { model.selectClip(clip.id) }
            dragSelection = model.selectedClips
            if duplicate {
                dragCopies = Dictionary(uniqueKeysWithValues: dragSelection.map { ($0, UUID()) })
                dragDuplicate = dragCopies[clip.id]
                model.selectedClips = Set(dragCopies.values)
            }
            focusRequest = UUID()
        }
        guard let base = dragBase, let original = base.clips.first(where: { $0.id == clip.id }) else { return nil }
        return (base, original)
    }
    private func commit(_ action: String) {
        if let draft { model.setTimeline(draft, action: action, undo: undo) }
        draft = nil; dragBase = nil; dragDuplicate = nil; dragSelection = []; dragCopies = [:]
    }

    // MARK: Inspector

    @ViewBuilder private func inspector(_ shown: Timeline) -> some View {
        if let clip = shown.clips.first(where: { model.selectedClips.contains($0.id) }) {
            VStack(alignment: .leading, spacing: Space.sm) {
                Text(model.selectedClips.count > 1 ? "\(model.selectedClips.count) clips selected" : (model.takeFor(clip)?.displayTitle ?? "Missing clip")).font(.headline)
                if model.selectedClips.count == 1 {
                    Text("Track \(clip.track + 1) · starts at \(preciseTimeLabel(clip.start)) · \(String(format: "%.2f", clip.length)) seconds · uses \(preciseTimeLabel(clip.inPoint))–\(preciseTimeLabel(clip.outPoint)) of the clip")
                        .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                }
                HStack(spacing: Space.sm) {
                    Button("Split at Playhead", systemImage: "scissors") { model.splitAtPlayhead(undo: undo) }
                    Button("Delete", systemImage: "trash") { model.deleteClip(ripple: false, undo: undo) }
                    Button("Ripple Delete") { model.deleteClip(ripple: true, undo: undo) }
                        .help("Delete selected clips and move later clips on their tracks left to close the gap (Shift-Delete)")
                }
            }.gridProbe("editor-clip", area: "editor-inspector")
        } else {
            Label("Drag clips onto a track. Shift-click to select multiple clips; Command-click to toggle. Drag to move the selection, Option-drag to duplicate, or drag its edges to trim. Cut/copy/paste with Command-X/C/V. Delete removes the selection. Split at the playhead with Command-B. Space plays the timeline.",
                  systemImage: "info.circle")
                .font(.callout).foregroundStyle(.secondary)
                .gridProbe("editor-hint", area: "editor-inspector")
        }
    }
}

struct EditorTransport: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undo
    var body: some View {
        let playback = model.playback
        let playing = model.isPlayingTimeline && playback.isPlaying
        let empty = model.timeline.isEmpty
        HStack(spacing: Space.md) {
            Button(playing ? "Pause" : "Play", systemImage: playing ? "pause.fill" : "play.fill") { model.toggleTimelinePlayback() }
                .labelStyle(.iconOnly).disabled(empty).help("Play or pause the timeline (Space)")
            Button("Go to Start", systemImage: "backward.end.fill") { model.seekTimeline(0) }
                .labelStyle(.iconOnly).help("Move the playhead to the start")
            Toggle("Loop", systemImage: "repeat", isOn: Binding(get: { model.timelineLoopEnabled }, set: { model.setTimelineLoopEnabled($0, undo: undo) }))
                .toggleStyle(.button).labelStyle(.iconOnly).disabled(empty)
                .help(model.timelineLoopEnabled ? "Repeat between the loop markers (Command-L)" : "Enable the loop markers (Command-L)")
            Text("\(preciseTimeLabel(model.timelineTime)) / \(preciseTimeLabel(model.timeline.duration))")
                .font(.callout).monospacedDigit().foregroundStyle(.secondary)
            Spacer(minLength: Space.md)
            Button("Split", systemImage: "scissors") { model.splitAtPlayhead(undo: undo) }
                .labelStyle(.iconOnly).disabled(empty).help("Split at the playhead (Command-B)")
            HStack(spacing: Space.xs) {
                Button("Zoom Out", systemImage: "minus.magnifyingglass") { model.zoom(by: 1 / 1.5) }
                    .labelStyle(.iconOnly).buttonStyle(.borderless).help("Zoom out (Command-Minus)")
                Slider(value: Binding(get: { log(model.zoom) }, set: { model.zoom = exp($0) }),
                       in: log(AppModel.zoomRange.lowerBound)...log(AppModel.zoomRange.upperBound))
                    .frame(width: 96).controlSize(.small).accessibilityLabel("Zoom")
                Button("Zoom In", systemImage: "plus.magnifyingglass") { model.zoom(by: 1.5) }
                    .labelStyle(.iconOnly).buttonStyle(.borderless).help("Zoom in (Command-Plus)")
            }
            Menu("Timeline") {
                Button("Save Timeline…") { model.saveTimeline() }
                Button("Load Timeline…") { model.loadTimeline(undo: undo) }
                Divider()
                Button("Set Loop Start at Playhead") { model.setLoopMarker(start: true, time: model.timelineTime, undo: undo) }
                    .disabled(empty)
                Button("Set Loop End at Playhead") { model.setLoopMarker(start: false, time: model.timelineTime, undo: undo) }
                    .disabled(empty)
            }.fixedSize().help("Save or load an editable timeline, or position loop markers")
            Menu("Export", systemImage: "square.and.arrow.up") {
                Button("Export as WAV…") { model.exportTimeline(.wav) }
                Button("Export as MP3…") { model.exportTimeline(.mp3) }
            }
            .fixedSize().disabled(empty).help("Mix every track into one audio file")
        }
    }
}

/// Seconds along the top of the timeline. Click or drag to move the playhead.
struct TimelineRuler: View {
    let pixelsPerSecond: Double
    var body: some View {
        Canvas { context, size in
            let steps = [0.1, 0.25, 0.5, 1, 2, 5, 10, 15, 30, 60, 120]
            let step = steps.first { $0 * pixelsPerSecond >= 64 } ?? 300
            let minor = step / 4
            var time = 0.0
            var index = 0
            while time * pixelsPerSecond <= size.width {
                let x = time * pixelsPerSecond
                let major = index.isMultiple(of: 4)
                var line = Path()
                line.move(to: CGPoint(x: x, y: size.height - (major ? 10 : 4)))
                line.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(line, with: .color(.secondary), lineWidth: 1)
                if major {
                    let label = step < 1 ? preciseTimeLabel(time) : timeLabel(time)
                    context.draw(Text(label).font(.caption2).monospacedDigit().foregroundStyle(.secondary),
                                 at: CGPoint(x: x + 4, y: 4), anchor: .topLeading)
                }
                index += 1
                time = Double(index) * minor
            }
        }
    }
}

/// The playhead line. Its own view, so only it redraws while audio plays.
struct Playhead: View {
    @Environment(AppModel.self) private var model
    let pixelsPerSecond: Double
    var body: some View {
        Rectangle().fill(Palette.accent)
            .frame(width: 2, height: EditorMetrics.height)
            .offset(x: max(1, model.timelineTime * pixelsPerSecond - 1)) // grid: ok timeline time-to-x placement
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { EditorProbe.playhead = $0 }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct ClipView: View {
    let clip: TimelineClip
    let take: SpeechTake?
    let peaks: [Float]?
    let selected: Bool
    let pixelsPerSecond: Double
    let muted: Bool
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: EditorMetrics.clipRadius, style: .continuous)
        ZStack(alignment: .topLeading) {
            shape.fill(Palette.accent.opacity(selected ? 0.32 : 0.18))
            if let peaks {
                Waveform(peaks: peaks, inPoint: clip.inPoint, pixelsPerSecond: pixelsPerSecond)
                    .fill(Palette.accent.opacity(0.8))
                    .padding(.top, Space.xl).padding(.bottom, Space.xs)
            }
            Text(take?.displayTitle ?? "Missing clip")
                .font(.caption).lineLimit(1)
                .foregroundStyle(take == nil ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
                .padding(.horizontal, Space.sm).padding(.top, Space.xs)
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Palette.accent.opacity(selected ? 1 : 0.5), lineWidth: selected ? 2 : 1))
        .opacity(muted ? 0.5 : 1)
        .contentShape(shape)
        .help(take?.displayTitle ?? "This clip was removed from the library.")
    }
}

/// Draws the loudest peak under each point, starting at the clip's in-point.
struct Waveform: Shape {
    let peaks: [Float]
    let inPoint: Double
    let pixelsPerSecond: Double
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let perPoint = 1 / (pixelsPerSecond * TimelineAudio.peakInterval)
        let mid = rect.midY
        var x = 0.0
        while x < rect.width {
            let first = Int((inPoint / TimelineAudio.peakInterval) + x * perPoint)
            let last = max(first + 1, Int((inPoint / TimelineAudio.peakInterval) + (x + 1) * perPoint))
            guard first < peaks.count else { break }
            let peak = peaks[first..<min(peaks.count, last)].max() ?? 0
            let height = max(1, CGFloat(peak) * rect.height)
            path.addRect(CGRect(x: rect.minX + x, y: mid - height / 2, width: 1, height: height))
            x += 1
        }
        return path
    }
}

/// Exposes the real scroll viewport for the rendered reset regression check.
struct TimelineScrollProbe: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { [weak view] in EditorProbe.scrollView = view?.enclosingScrollView }
    }
}

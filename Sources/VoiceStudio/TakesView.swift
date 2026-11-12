import SwiftUI
import VoiceStudioKit

struct TakeList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undo
    @State private var search = ""
    var visible: [SpeechTake] { model.takes.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.voiceName.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        @Bindable var model = model
        List(visible, selection: $model.selectedTakes) { take in
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(take.displayTitle).lineLimit(1).help(take.displayTitle)
                Text(take.voiceName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                HStack {
                    Label(take.status.title, systemImage: take.status.symbol)
                    Spacer()
                    if take.status == .completed { Text(timeLabel(take.duration)).monospacedDigit() }
                }.font(.caption).foregroundStyle(.secondary)
            }.padding(.vertical, Space.xs).tag(take.id)
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            let selected = model.takes.filter { ids.contains($0.id) }
            if selected.count == 1, let take = selected.first, take.status == .completed {
                Button("Play/Pause") { model.play(take) }
                Button("Export Clip…") { model.export(take) }
                Button("Show in Finder") { model.reveal(take) }
            }
            Button("Generate Selected Again") { model.retryTakes(ids) }.disabled(!selected.contains { $0.importedFilename == nil && ![.queued, .running].contains($0.status) })
            Button("Remove Selected Clips", role: .destructive) { model.removeTakes(ids, undo: undo) }
                .disabled(!selected.contains { ![.queued, .running].contains($0.status) })
        }
        .onDeleteCommand { model.removeTakes(model.selectedTakes, undo: undo) }
        // The macOS List gives a row inserted while it shows a one-line height, so a new clip
        // lost its voice, status, and duration. Rebuild the list when clips are added or removed.
        .id(visible.map(\.id))
        .overlay {
            if model.takes.isEmpty {
                ContentUnavailableView("No Clips", systemImage: "waveform", description: Text("Generate speech from Scripts. Every clip will be saved here."))
            } else if visible.isEmpty { ContentUnavailableView.search(text: search) }
        }
        .searchable(text: $search, prompt: "Find a clip or voice")
        .navigationTitle("Clips")
        .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 400)
    }
}
struct TakeDetail: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        if let take = model.take {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Text(take.displayTitle).font(.title2).textSelection(.enabled)
                        if model.selectedTakes.count > 1 {
                            Text("\(model.selectedTakes.count) clips selected · previewing \(take.displayTitle)")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        Label(take.status.title, systemImage: take.status.symbol).foregroundStyle(.secondary)
                    }.gridProbe("take-title", area: "take-page")
                    if take.status == .completed {
                        AudioTransport(url: take.audioURL(relativeTo: Store.root)).gridProbe("take-player", area: "take-page")
                        HStack(spacing: Space.sm) {
                            Button("Export Clip…", systemImage: "square.and.arrow.up") { model.export(take) }
                            Button("Show in Finder", systemImage: "folder") { model.reveal(take) }
                            if take.importedFilename == nil { Button(model.selectedTakes.count > 1 ? "Generate Selected Again" : "Generate Again") { model.retryTakes(model.selectedTakes) } }
                        }.gridProbe("take-actions", area: "take-page")
                    } else if take.status == .failed || take.status == .canceled {
                        VStack(alignment: .leading, spacing: Space.sm) {
                            Text(take.error.isEmpty ? "Generation was canceled. Your script and settings are retained." : take.error)
                                .foregroundStyle(.secondary).textSelection(.enabled)
                            Button(model.selectedTakes.count > 1 ? "Retry Selected as New Clips" : "Retry as New Clip") { model.retryTakes(model.selectedTakes) }
                        }.gridProbe("take-error", area: "take-page")
                    } else {
                        HStack(spacing: Space.sm) {
                            ProgressView().controlSize(.small)
                            Text(take.status == .running ? model.progress : "Waiting in the queue")
                        }.gridProbe("take-progress", area: "take-page")
                    }
                    Grid(alignment: .leading, horizontalSpacing: Space.xl, verticalSpacing: Space.sm) {
                        if let filename = take.importedFilename {
                            metadata("Source file", filename)
                            metadata("Duration", String(format: "%.2f seconds", take.duration))
                        } else {
                            metadata("Voice", take.voiceName)
                            metadata("Voice source", take.cachedVoice != nil ? "Imported XTTS cache" : (take.references.isEmpty ? "Built-in voice" : "Reference audio"))
                            metadata("Language", Languages.name(take.language))
                            metadata("Speed", String(format: "%.2f×", take.speed))
                            metadata("Model", take.modelName)
                            metadata("Device", take.device == "mps" ? "Apple GPU" : "CPU")
                            metadata("Seed", String(take.seed))
                            if take.status == .completed {
                                metadata("Duration", String(format: "%.2f seconds", take.duration))
                                metadata("Generated in", String(format: "%.2f seconds", take.generationSeconds))
                            }
                        }
                    }.font(.callout).textSelection(.enabled).gridProbe("take-metadata", area: "take-page")
                    if take.importedFilename == nil {
                        VStack(alignment: .leading, spacing: Space.sm) {
                            Text("Source Text").font(.headline)
                            Text(take.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }.gridProbe("take-source", area: "take-page")
                    }
                }.padding(Space.margin).frame(maxWidth: .infinity, alignment: .leading).gridArea("take-page")
            }
        } else {
            ContentUnavailableView("Select a Clip", systemImage: "waveform", description: Text("Listen to alternate clips, inspect their settings, and export audio."))
        }
    }
    private func metadata(_ key: String, _ value: String) -> some View {
        GridRow { Text(key).foregroundStyle(.secondary); Text(value) }
    }
}
struct AudioTransport: View {
    @Environment(AppModel.self) private var model
    let url: URL
    var body: some View {
        let playback = model.playback
        let current = playback.url == url
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.md) {
                Button(current && playback.isPlaying ? "Pause" : "Play", systemImage: current && playback.isPlaying ? "pause.fill" : "play.fill") {
                    do { try playback.toggle(url) } catch { model.message = "Unable to play audio: \(error.localizedDescription)" }
                }
                Toggle("Loop", systemImage: "repeat", isOn: Binding(get: { playback.loops }, set: { playback.loops = $0 }))
                    .toggleStyle(.button).labelStyle(.iconOnly)
                    .help(playback.loops ? "Looping is on (Command-L)" : "Loop playback (Command-L)")
                Slider(value: Binding(get: { current ? playback.position : 0 }, set: { playback.seek($0) }), in: 0...max(1, current ? playback.duration : 1))
                    .disabled(!current).accessibilityLabel("Playback position")
                Text(current ? "\(timeLabel(playback.position)) / \(timeLabel(playback.duration))" : "Ready to play")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary).frame(minWidth: 80, alignment: .trailing)
            }
        }
    }
}

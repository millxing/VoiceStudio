import SwiftUI
import VoiceStudioKit

struct TakeList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undo
    @State private var search = ""
    var visible: [SpeechTake] { model.takes.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.voiceName.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        @Bindable var model = model
        List(visible, selection: $model.selectedTake) { take in
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(take.displayTitle).lineLimit(1).help(take.displayTitle)
                Text(take.voiceName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                HStack {
                    Label(take.status.title, systemImage: take.status.symbol)
                    Spacer()
                    if take.status == .completed { Text(timeLabel(take.duration)).monospacedDigit() }
                }.font(.caption).foregroundStyle(.secondary)
            }.padding(.vertical, Space.xs).tag(take.id)
                .contextMenu {
                    if take.status == .completed {
                        Button("Play/Pause") { model.play(take) }
                        Button("Export Take…") { model.export(take) }
                        Button("Show in Finder") { model.reveal(take) }
                    }
                    if ![.queued, .running].contains(take.status) {
                        Button("Generate Again") { model.retry(take) }
                        Button("Remove Take", role: .destructive) { model.removeTake(take, undo: undo) }
                    }
                }
        }
        .overlay {
            if model.takes.isEmpty {
                ContentUnavailableView("No Takes", systemImage: "waveform", description: Text("Generate speech from Scripts. Every take will be saved here."))
            } else if visible.isEmpty { ContentUnavailableView.search(text: search) }
        }
        .searchable(text: $search, prompt: "Find a take or voice")
        .navigationTitle("Takes")
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
                        Label(take.status.title, systemImage: take.status.symbol).foregroundStyle(.secondary)
                    }.gridProbe("take-title", area: "take-page")
                    if take.status == .completed {
                        AudioTransport(url: Store.root.appending(path: take.audioFile)).gridProbe("take-player", area: "take-page")
                        HStack(spacing: Space.sm) {
                            Button("Export Take…", systemImage: "square.and.arrow.up") { model.export(take) }
                            Button("Show in Finder", systemImage: "folder") { model.reveal(take) }
                            Button("Generate Again") { model.retry(take) }
                        }.gridProbe("take-actions", area: "take-page")
                    } else if take.status == .failed || take.status == .canceled {
                        VStack(alignment: .leading, spacing: Space.sm) {
                            Text(take.error.isEmpty ? "Generation was canceled. Your script and settings are retained." : take.error)
                                .foregroundStyle(.secondary).textSelection(.enabled)
                            Button("Retry as New Take") { model.retry(take) }
                        }.gridProbe("take-error", area: "take-page")
                    } else {
                        HStack(spacing: Space.sm) {
                            ProgressView().controlSize(.small)
                            Text(take.status == .running ? model.progress : "Waiting in the queue")
                        }.gridProbe("take-progress", area: "take-page")
                    }
                    Grid(alignment: .leading, horizontalSpacing: Space.xl, verticalSpacing: Space.sm) {
                        metadata("Voice", take.voiceName)
                        metadata("Language", Languages.name(take.language))
                        metadata("Speed", String(format: "%.2f×", take.speed))
                        metadata("Model", take.modelName)
                        metadata("Device", take.device == "mps" ? "Apple GPU" : "CPU")
                        metadata("Seed", String(take.seed))
                        if take.status == .completed {
                            metadata("Duration", String(format: "%.2f seconds", take.duration))
                            metadata("Generated in", String(format: "%.2f seconds", take.generationSeconds))
                        }
                    }.font(.callout).textSelection(.enabled).gridProbe("take-metadata", area: "take-page")
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Text("Source Text").font(.headline)
                        Text(take.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }.gridProbe("take-source", area: "take-page")
                }.padding(Space.margin).frame(maxWidth: .infinity, alignment: .leading).gridArea("take-page")
            }
        } else {
            ContentUnavailableView("Select a Take", systemImage: "waveform", description: Text("Listen to alternate takes, inspect their settings, and export audio."))
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
                Slider(value: Binding(get: { current ? playback.position : 0 }, set: { playback.seek($0) }), in: 0...max(1, current ? playback.duration : 1))
                    .disabled(!current).accessibilityLabel("Playback position")
                Text(current ? "\(timeLabel(playback.position)) / \(timeLabel(playback.duration))" : "Ready to play")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary).frame(minWidth: 80, alignment: .trailing)
            }
        }
    }
}

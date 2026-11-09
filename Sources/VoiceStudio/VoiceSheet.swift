import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VoiceStudioKit

struct VoiceSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let existing: VoiceReference?
    @State private var name: String
    @State private var urls: [URL]
    @State private var source: String
    @State private var cachedURL: URL?
    @State private var entries: [CachedVoiceEntry] = []
    @State private var entry = ""
    @State private var inspecting = false
    @State private var saving = false
    @State private var importTask: Task<Void, Never>?
    @State private var temporaryFiles = [URL]()
    @State private var error = ""
    @State private var recorder = VoiceRecorder()
    init(existing: VoiceReference?) {
        self.existing = existing
        _name = State(initialValue: existing?.name ?? "")
        _urls = State(initialValue: existing?.files.map { Store.root.appending(path: $0) } ?? [])
        _source = State(initialValue: existing?.cachedFile == nil ? "audio" : "cache")
        _cachedURL = State(initialValue: existing?.cachedFile.map { Store.root.appending(path: $0) })
    }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !recorder.recording && !inspecting && !saving
            && (source == "audio" ? !urls.isEmpty : cachedURL != nil)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            Text(existing == nil ? "Add Voice" : "Edit Voice").font(.title2).gridProbe("sheet-title", area: "voice-sheet")
            TextField("Voice name", text: $name).textFieldStyle(.roundedBorder).disabled(saving).gridProbe("sheet-name", area: "voice-sheet")
            Picker("Voice source", selection: $source) {
                Text("Reference Audio").tag("audio")
                Text("Cached Voice (.pth)").tag("cache")
            }.pickerStyle(.segmented).disabled(recorder.recording || inspecting || saving).gridProbe("sheet-source", area: "voice-sheet")
            Text(source == "audio" ? "Import clean speech or record a reference. Multiple clips can help capture the voice. Start with about 6–15 seconds of a single speaker." : "Import saved XTTS voice conditioning from a .pth file. If the file contains several speakers, choose one to save as this voice.")
                .foregroundStyle(.secondary).gridProbe("sheet-guidance", area: "voice-sheet")
            Group {
                if source == "audio" { referenceControls }
                else { cacheControls }
            }.gridProbe("sheet-references", area: "voice-sheet")
            if !(error.isEmpty && recorder.error.isEmpty) {
                Label(error.isEmpty ? recorder.error : error, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(saving)
                Button(saving ? "Saving…" : "Save Voice") { save() }.keyboardShortcut(.defaultAction).disabled(!canSave)
            }.gridProbe("sheet-actions", area: "voice-sheet", edge: nil)
        }.padding(Space.margin).frame(width: 640).gridArea("voice-sheet").noInitialFocus()
            .onChange(of: entry) { old, new in
                if let previous = entries.first(where: { $0.id == old }), name == previous.name,
                   let selected = entries.first(where: { $0.id == new }) { name = selected.name }
            }
            .onDisappear {
                importTask?.cancel()
                recorder.cancel(); model.playback.stop()
                if let url = recorder.temporaryURL, !temporaryFiles.contains(url) { temporaryFiles.append(url) }
                for url in temporaryFiles { try? FileManager.default.removeItem(at: url) }
            }
    }
    private var referenceControls: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(spacing: Space.sm) {
                Button("Import Audio…", systemImage: "square.and.arrow.down") { importAudio() }.disabled(recorder.recording || saving)
                if recorder.recording {
                    Button("Stop Recording", systemImage: "stop.fill") {
                        if let url = recorder.stop() { urls.append(url); temporaryFiles.append(url) }
                    }
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(timeLabel(context.date.timeIntervalSince(recorder.started))).monospacedDigit().foregroundStyle(.secondary)
                    }
                } else {
                    Button("Record", systemImage: "mic") { model.playback.stop(); Task { await recorder.start() } }.disabled(saving)
                }
            }
            if urls.isEmpty {
                Text("No reference clips added").font(.callout).foregroundStyle(.secondary).padding(.vertical, Space.lg)
            } else {
                ScrollView {
                    VStack(spacing: Space.md) {
                        ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                            VStack(alignment: .leading, spacing: Space.sm) {
                                HStack {
                                    Text("Reference \(index + 1) · \(url.lastPathComponent)").lineLimit(1).help(url.lastPathComponent)
                                    Spacer()
                                    Button("Remove") { urls.remove(at: index) }.disabled(recorder.recording || saving)
                                }
                                AudioTransport(url: url)
                            }
                        }
                    }
                }.frame(maxHeight: 200)
            }
        }
    }
    private var cacheControls: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(spacing: Space.sm) {
                Button("Import Cached Voice…", systemImage: "square.and.arrow.down") { importCache() }.disabled(inspecting || saving)
                if inspecting || saving { ProgressView().controlSize(.small) }
            }
            if let cachedURL {
                Label(existing?.cachedFile != nil && entries.isEmpty ? "Saved XTTS voice" : cachedURL.lastPathComponent, systemImage: "person.wave.2").lineLimit(1)
                if entries.count > 1 {
                    Picker("Saved speaker", selection: $entry) {
                        ForEach(entries) { choice in Text(choice.name).tag(choice.id) }
                    }.disabled(saving)
                }
                Text("Cached voices contain no playable recording. Generate a clip to preview this voice.").font(.callout).foregroundStyle(.secondary)
            } else {
                Text(inspecting ? "Checking saved voices…" : "No cached voice selected").font(.callout).foregroundStyle(.secondary).padding(.vertical, Space.lg)
            }
        }
    }
    private func importAudio() {
        let panel = NSOpenPanel(); panel.title = "Import Voice References"
        panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        panel.allowedContentTypes = [.wav, .mp3, .aiff, .mpeg4Audio, UTType(filenameExtension: "flac")!]
        if panel.runModal() == .OK { urls.append(contentsOf: panel.urls) }
    }
    private func importCache() {
        let panel = NSOpenPanel(); panel.title = "Import XTTS Cached Voice"
        panel.allowedContentTypes = [UTType(filenameExtension: "pth") ?? .data]
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        inspecting = true; error = ""; cachedURL = nil; entries = []; entry = ""
        importTask = Task {
            defer { inspecting = false }
            do {
                let found = try await CachedVoiceImport.inspect(url, python: model.preferences.python)
                try Task.checkCancellation()
                entries = found; entry = found[0].id; cachedURL = url
                if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { name = found[0].name }
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }
    private func save() {
        error = ""
        if source == "audio" {
            do { try model.storeVoice(name: name, urls: urls, existing: existing); dismiss() }
            catch { self.error = error.localizedDescription }
        } else if let cachedURL {
            saving = true
            importTask = Task {
                defer { saving = false }
                do {
                    try await model.storeCachedVoice(name: name, source: cachedURL, entry: entry, existing: existing)
                    dismiss()
                } catch is CancellationError { }
                catch { self.error = error.localizedDescription }
            }
        }
    }
}

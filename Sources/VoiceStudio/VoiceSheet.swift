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
    @State private var temporaryFiles = [URL]()
    @State private var error = ""
    @State private var recorder = VoiceRecorder()
    init(existing: VoiceReference?) {
        self.existing = existing
        _name = State(initialValue: existing?.name ?? "")
        _urls = State(initialValue: existing?.files.map { Store.root.appending(path: $0) } ?? [])
    }
    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            Text(existing == nil ? "Add Voice" : "Edit Voice").font(.title2).gridProbe("sheet-title", area: "voice-sheet")
            TextField("Voice name", text: $name).textFieldStyle(.roundedBorder).gridProbe("sheet-name", area: "voice-sheet")
            Text("Import clean speech or record a reference. Multiple clips can help capture the voice. Start with about 6–15 seconds of a single speaker.")
                .foregroundStyle(.secondary).gridProbe("sheet-guidance", area: "voice-sheet")
            VStack(alignment: .leading, spacing: Space.md) {
                HStack(spacing: Space.sm) {
                    Button("Import Audio…", systemImage: "square.and.arrow.down") { importAudio() }.disabled(recorder.recording)
                    if recorder.recording {
                        Button("Stop Recording", systemImage: "stop.fill") {
                            if let url = recorder.stop() { urls.append(url); temporaryFiles.append(url) }
                        }
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(timeLabel(context.date.timeIntervalSince(recorder.started))).monospacedDigit().foregroundStyle(.secondary)
                        }
                    } else {
                        Button("Record", systemImage: "mic") { model.playback.stop(); Task { await recorder.start() } }
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
                                        Button("Remove") { urls.remove(at: index) }.disabled(recorder.recording)
                                    }
                                    AudioTransport(url: url)
                                }
                            }
                        }
                    }.frame(maxHeight: 200)
                }
            }.gridProbe("sheet-references", area: "voice-sheet")
            if !(error.isEmpty && recorder.error.isEmpty) {
                Label(error.isEmpty ? recorder.error : error, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save Voice") { save() }.keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || urls.isEmpty || recorder.recording)
            }.gridProbe("sheet-actions", area: "voice-sheet", edge: nil)
        }.padding(Space.margin).frame(width: 640).gridArea("voice-sheet").noInitialFocus()
            .onDisappear {
                recorder.cancel(); model.playback.stop()
                if let url = recorder.temporaryURL, !temporaryFiles.contains(url) { temporaryFiles.append(url) }
                for url in temporaryFiles { try? FileManager.default.removeItem(at: url) }
            }
    }
    private func importAudio() {
        let panel = NSOpenPanel(); panel.title = "Import Voice References"
        panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        panel.allowedContentTypes = [.wav, .mp3, .aiff, .mpeg4Audio, UTType(filenameExtension: "flac")!]
        if panel.runModal() == .OK { urls.append(contentsOf: panel.urls) }
    }
    private func save() {
        do { try model.storeVoice(name: name, urls: urls, existing: existing); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

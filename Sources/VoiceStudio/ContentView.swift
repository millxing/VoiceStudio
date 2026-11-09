import AppKit
import SwiftUI
import VoiceStudioKit

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            VStack(spacing: 0) {
                List(SidebarItem.allCases, selection: $model.sidebar) { page in
                    Label(page.title, systemImage: page.symbol).tag(page)
                }
                VStack(alignment: .leading, spacing: Space.sm) {
                    Label(model.engine.status, systemImage: model.engine.isReady ? "circle.fill" : "circle")
                        .font(.caption).foregroundStyle(.secondary)
                    if model.queueRunning {
                        ProgressView(value: Double(model.completedInBatch), total: Double(max(1, model.batchTotal)))
                        Text("\(model.completedInBatch) of \(model.batchTotal) takes finished").font(.caption).foregroundStyle(.secondary)
                        Text(model.progress).font(.caption).foregroundStyle(.secondary).lineLimit(2).help(model.progress)
                        Button("Stop Queue", systemImage: "stop.fill") { model.stopQueue() }
                    } else if model.queuedCount > 0 {
                        Button("Resume \(model.queuedCount) Queued Takes") { model.resumeQueue() }
                    }
                }
                .padding(Space.lg)
            }
            .navigationSplitViewColumnWidth(min: 188, ideal: 208, max: 260)
        } content: {
            switch model.sidebar ?? .scripts {
            case .scripts: ScriptList()
            case .voices: VoiceList()
            case .takes: TakeList()
            }
        } detail: {
            VStack(spacing: 0) {
                if !model.message.isEmpty {
                    HStack(alignment: .top, spacing: Space.sm) {
                        Label(model.message, systemImage: "exclamationmark.triangle").textSelection(.enabled)
                        Spacer()
                        Button("Dismiss") { model.message = "" }
                    }.font(.callout).padding(Space.lg).background(.quaternary)
                    Divider()
                }
                switch model.sidebar ?? .scripts {
                case .scripts: ScriptDetail()
                case .voices: VoiceDetail()
                case .takes: TakeDetail()
                }
            }
        }
        .noInitialFocus()
        .sheet(isPresented: $model.showingVoiceSheet) {
            VoiceSheet(existing: model.editingVoice).environment(model).themed()
        }
        .sheet(isPresented: $model.showingEngineSetup) { EngineSetupView().environment(model).themed() }
        .task {
            SeedData.insertIfRequested(into: model)
            SelfTest.runIfRequested(model: model)
            Snapshot.runIfRequested(model: model, openSettings: openSettings)
            if !Store.isOverridden && !SelfTest.requested { model.startOrSetUpEngine() }
        }
    }
}
struct ScriptList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undo
    var body: some View {
        @Bindable var model = model
        List(selection: $model.selectedScripts) {
            ForEach(model.scripts) { script in
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(script.title.isEmpty ? "Untitled Script" : script.title).lineLimit(1).help(script.title)
                    Text(script.text.isEmpty ? "No text yet" : script.text.replacingOccurrences(of: "\n", with: " "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }.padding(.vertical, Space.xs).tag(script.id)
                .contextMenu {
                    Button("Generate Script") { model.selectedScripts = [script.id]; model.queue() }
                        .disabled(script.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Remove Script", role: .destructive) { model.removeScripts([script.id], undo: undo) }
                }
            }
        }
        .overlay {
            if model.scripts.isEmpty {
                ContentUnavailableView {
                    Label("No Scripts", systemImage: "doc.text")
                } description: { Text("Write a script or import text files to turn them into speech.") }
                actions: { Button("New Script") { model.addScript() }; Button("Import Text Files…") { model.importScripts() } }
            }
        }
        .navigationTitle("Scripts")
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 400)
        .toolbar {
            ToolbarItemGroup {
                Button("New Script", systemImage: "square.and.pencil") { model.addScript() }.help("Create a script (Command-N)")
                Button("Import Text Files…", systemImage: "square.and.arrow.down") { model.importScripts() }.help("Import multiple text files (Command-O)")
            }
        }
    }
}
struct ScriptDetail: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        if let script = model.selectedScript {
            VStack(alignment: .leading, spacing: Space.lg) {
                VStack(alignment: .leading, spacing: Space.sm) {
                    TextField("Script title", text: Binding(get: { model.scripts.first { $0.id == script.id }?.title ?? "" },
                        set: { model.updateScript(script.id, title: $0) }))
                        .font(.title2).textFieldStyle(.plain).accessibilityLabel("Script title")
                    Text(model.selectedScripts.count > 1 ? "\(model.selectedScripts.count) scripts selected · editing \(script.title)" : "\(script.text.count.formatted()) characters · saved automatically")
                        .font(.caption).foregroundStyle(.secondary)
                }.gridProbe("script-title", area: "script-page")
                TextEditor(text: Binding(get: { model.scripts.first { $0.id == script.id }?.text ?? "" },
                    set: { model.updateScript(script.id, text: $0) }))
                    .font(.body).scrollContentBackground(.hidden)
                    .padding(Space.sm)
                    .background(.background, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
                    .accessibilityLabel("Script text")
                    .frame(minHeight: 160)
                    .gridProbe("script-editor", area: "script-page")
                GenerationControls().gridProbe("script-controls", area: "script-page")
            }
            .padding(Space.margin).gridArea("script-page")
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ContentUnavailableView("Select a Script", systemImage: "doc.text", description: Text("Choose a script to edit its text and generate speech."))
        }
    }
}
struct GenerationControls: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: Space.lg) {
            Grid(alignment: .leading, horizontalSpacing: Space.md, verticalSpacing: Space.md) {
                GridRow {
                    Text("Voice").foregroundStyle(.secondary)
                    Picker("Voice", selection: $model.preferences.voice) {
                        if !model.voices.isEmpty {
                            Section("Cloned Voices") {
                                ForEach(model.voices) { voice in Text(voice.name).tag("clone:\(voice.id.uuidString)") }
                            }
                        }
                        Section("Built-in Voices") {
                            ForEach(model.engine.speakers, id: \.self) { name in Text(name).tag("builtin:\(name)") }
                        }
                    }.labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
                    Button("Add Voice…") { model.addVoice() }
                }
                GridRow {
                    Text("Language").foregroundStyle(.secondary)
                    Picker("Language", selection: $model.preferences.language) {
                        ForEach(Languages.all, id: \.0) { code, name in Text(name).tag(code) }
                    }.labelsHidden()
                    Stepper("Takes: \(model.preferences.takes)", value: $model.preferences.takes, in: 1...20)
                        .help("Generate this many alternate takes for each selected script")
                }
                GridRow {
                    Text("Speed").foregroundStyle(.secondary)
                    HStack(spacing: Space.md) {
                        Slider(value: $model.preferences.speed, in: 0.1...1.99, step: 0.01).accessibilityLabel("Speech speed")
                        Text("\(model.preferences.speed, specifier: "%.2f")×").monospacedDigit().frame(width: 48, alignment: .trailing)
                        Button("Reset") { model.preferences.speed = 1.0 }.controlSize(.small)
                    }.gridCellColumns(2)
                }
            }
            HStack(spacing: Space.md) {
                Text("\(model.selectedScripts.count) \(model.selectedScripts.count == 1 ? "script" : "scripts") × \(model.preferences.takes) \(model.preferences.takes == 1 ? "take" : "takes")")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Generate Selected", systemImage: "waveform.badge.plus") { model.queue() }
                    .buttonStyle(.borderedProminent).disabled(!model.canGenerate)
                    .help("Generate takes for the selected scripts (Command-G)")
            }
        }
    }
}
struct VoiceList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undo
    var body: some View {
        @Bindable var model = model
        List(model.voices, selection: $model.selectedVoice) { voice in
            VStack(alignment: .leading, spacing: Space.xs) {
                Label(voice.name, systemImage: "person.wave.2").lineLimit(1).help(voice.name)
                Text(voice.cachedFile == nil ? "\(voice.files.count) reference \(voice.files.count == 1 ? "clip" : "clips")" : "Imported XTTS cache").font(.caption).foregroundStyle(.secondary)
            }.padding(.vertical, Space.xs).tag(voice.id)
                .contextMenu {
                    Button("Edit Voice…") { model.editingVoice = voice; model.showingVoiceSheet = true }
                    Button("Remove Voice", role: .destructive) { model.removeVoice(voice, undo: undo) }
                }
        }
        .overlay {
            if model.voices.isEmpty {
                ContentUnavailableView {
                    Label("No Cloned Voices", systemImage: "person.wave.2")
                } description: { Text("Import or record a few seconds of speech to create a voice.") }
                actions: { Button("Add Voice…") { model.addVoice() } }
            }
        }
        .navigationTitle("Voices")
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 400)
        .toolbar { ToolbarItem { Button("Add Voice…", systemImage: "person.badge.plus") { model.addVoice() }.help("Import or record a cloned voice (Shift-Command-V)") } }
    }
}
struct VoiceDetail: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        if let voice = model.voice {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Text(voice.name).font(.title2).textSelection(.enabled)
                        Text(voice.cachedFile == nil ? "Cloned voice · \(voice.files.count) reference \(voice.files.count == 1 ? "clip" : "clips")" : "Cloned voice · imported XTTS cache").foregroundStyle(.secondary)
                    }.gridProbe("voice-title", area: "voice-page")
                    Text(voice.cachedFile == nil ? "Use clean speech with a single speaker and little background noise. Around 6–15 seconds per clip is a useful starting point." : "This voice uses saved XTTS conditioning. The original reference recordings are not required. Generate a take to preview it.")
                        .foregroundStyle(.secondary).gridProbe("voice-guidance", area: "voice-page")
                    VStack(alignment: .leading, spacing: Space.lg) {
                        ForEach(Array(voice.files.enumerated()), id: \.offset) { index, file in
                            VStack(alignment: .leading, spacing: Space.sm) {
                                Text("Reference \(index + 1)").font(.headline)
                                AudioTransport(url: Store.root.appending(path: file))
                            }
                        }
                    }.gridProbe("voice-clips", area: "voice-page")
                    HStack(spacing: Space.sm) {
                        Button("Use This Voice", systemImage: "waveform") { model.preferences.voice = "clone:\(voice.id.uuidString)"; model.sidebar = .scripts }
                        Button("Edit Voice…") { model.editingVoice = voice; model.showingVoiceSheet = true }
                    }.gridProbe("voice-actions", area: "voice-page")
                }.padding(Space.margin).frame(maxWidth: .infinity, alignment: .leading).gridArea("voice-page")
            }
        } else {
            ContentUnavailableView("Select a Voice", systemImage: "person.wave.2", description: Text("Preview a voice's reference clips or add a new voice."))
        }
    }
}

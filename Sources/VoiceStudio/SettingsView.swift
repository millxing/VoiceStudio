import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.settingsTab) {
            Form { EngineSettings() }
                .formStyle(.grouped).fitsContent().frame(width: 640)
                .tabItem { Label("Engine", systemImage: "waveform") }.tag(SettingsTab.engine)
            Form { AppearanceSettings() }
                .formStyle(.grouped).fitsContent().frame(width: 520)
                .tabItem { Label("Appearance", systemImage: "paintpalette") }.tag(SettingsTab.appearance)
        }.noInitialFocus()
    }
}
enum SettingsTab: String, CaseIterable, Identifiable {
    case engine, appearance
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String { self == .engine ? "waveform" : "paintpalette" }
}
struct EngineSettings: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model = model
        Section("Speech Engine") {
            Picker("Run on", selection: $model.preferences.device) {
                Text("Apple GPU (Metal)").tag("mps")
                Text("CPU").tag("cpu")
            }.disabled(model.queueRunning)
            LabeledContent("Model") {
                HStack {
                    Text(model.preferences.modelFolder.isEmpty ? "XTTS-v2 (downloaded model)" : URL(fileURLWithPath: model.preferences.modelFolder).lastPathComponent)
                        .lineLimit(1).help(model.preferences.modelFolder)
                    Button("Choose Folder…") { chooseModel() }
                    if !model.preferences.modelFolder.isEmpty { Button("Use Default") { model.preferences.modelFolder = "" } }
                }
            }.disabled(model.queueRunning)
            Text("A custom XTTS folder must contain model.pth, config.json, and vocab.json. Restart the engine after changing these settings.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Play each completed take automatically", isOn: $model.preferences.autoplay)
        }
        Section("Local Python Runtime") {
            TextField("Python interpreter", text: $model.preferences.python).textFieldStyle(.roundedBorder)
                .disabled(model.queueRunning)
            HStack {
                Button("Choose Python…") { choosePython() }.disabled(model.queueRunning)
                Button("Restart Engine") { model.restartEngine() }.disabled(model.queueRunning)
                Button("Open Engine Log") { NSWorkspace.shared.open(model.logURL) }
            }
            Label(model.engine.status, systemImage: model.engine.isReady ? "checkmark.circle" : "circle")
            if !model.engine.lastError.isEmpty {
                Text(model.engine.lastError).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Text("Uses the isolated XTTS environment installed on this Mac. Speech and reference audio stay local. The first load may need internet access to download model files.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section("Library") {
            LabeledContent("Location") { Text(Store.root.path).textSelection(.enabled).lineLimit(2) }
            Button("Show Library in Finder") { NSWorkspace.shared.open(Store.root) }
            Text("Scripts, voices, and takes are saved automatically. Removing a voice or take from the library retains its source audio for Undo and future editing.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private func choosePython() {
        let panel = NSOpenPanel(); panel.title = "Choose XTTS Python Interpreter"; panel.showsHiddenFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { model.preferences.python = url.path }
    }
    private func chooseModel() {
        let panel = NSOpenPanel(); panel.title = "Choose XTTS Model Folder"; panel.canChooseDirectories = true; panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url { model.preferences.modelFolder = url.path }
    }
}

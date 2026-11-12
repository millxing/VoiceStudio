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
            Form { StorageSettings() }
                .formStyle(.grouped).fitsContent().frame(width: 640)
                .tabItem { Label("Storage", systemImage: "folder") }.tag(SettingsTab.storage)
            Form { AppearanceSettings(); ScriptEditorSettings() }
                .formStyle(.grouped).fitsContent().frame(width: 520)
                .tabItem { Label("Appearance", systemImage: "paintpalette") }.tag(SettingsTab.appearance)
        }.noInitialFocus()
    }
}
enum SettingsTab: String, CaseIterable, Identifiable {
    case engine, storage, appearance
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self { case .engine: "waveform"; case .storage: "folder"; case .appearance: "paintpalette" }
    }
}
struct EngineSettings: View {
    @State private var showingSetup = false
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
            Toggle("Play each completed clip automatically", isOn: $model.preferences.autoplay)
        }
        Section("Local Python Runtime") {
            Button("Install Speech Engine…") { showingSetup = true }
                .sheet(isPresented: $showingSetup) { EngineSetupView().environment(model).themed() }
                .disabled(model.queueRunning || model.installer.running)
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
            Text("Uses the isolated XTTS environment installed on this Mac. Speech and reference audio stay local. Use Install Speech Engine to download and verify a managed runtime on this Mac.")
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

struct StorageSettings: View {
    @Environment(AppModel.self) private var model
    @State private var error = ""
    var body: some View {
        Section("Clips") {
            LabeledContent("Save new clips to") {
                Text(model.takesFolder.path).textSelection(.enabled).lineLimit(3)
            }
            HStack {
                Button("Choose Folder…") { chooseFolder() }
                if model.preferences.takesFolder != nil {
                    Button("Use Default Folder") {
                        do { try model.setTakesFolder(nil); error = "" }
                        catch { self.error = error.localizedDescription }
                    }
                }
            }.disabled(model.queueRunning)
            Text("New clips use this folder. Existing clips stay in their original locations and remain available for playback and export.")
                .font(.caption).foregroundStyle(.secondary)
            if !error.isEmpty { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary) }
        }
        Section("Exports and Timelines") {
            LabeledContent("Folder") { Text(model.exportFolder.path).textSelection(.enabled).lineLimit(3) }
            Button("Choose Export Folder…") { model.chooseExportFolder() }
            Text("Audio exports and saved timelines start in this folder. Saved timelines include their source audio.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section("Library") {
            LabeledContent("Location") { Text(Store.root.path).textSelection(.enabled).lineLimit(3) }
            Button("Show Library in Finder") { NSWorkspace.shared.open(Store.root) }
            Text("Scripts, voices, and settings stay in the library. Back up this folder and any separate clips folders.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Clips Folder"; panel.prompt = "Choose"
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.directoryURL = model.takesFolder
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        do { try model.setTakesFolder(folder); error = "" }
        catch { self.error = error.localizedDescription }
    }
}
struct ScriptEditorSettings: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model = model
        Section("Script Editor") {
            LabeledContent("Font size") {
                HStack(spacing: Space.sm) {
                    TextField("Font size", value: $model.preferences.scriptFont, format: .number.precision(.fractionLength(0)))
                        .labelsHidden().multilineTextAlignment(.trailing).frame(width: 48)
                    Stepper("Font size", value: $model.preferences.scriptFont, in: StudioPreferences.scriptFontSizes, step: 1).labelsHidden()
                    Text("pt").foregroundStyle(.secondary)
                    Button("Use Default") { model.preferences.scriptFontSize = nil }
                        .disabled(model.preferences.scriptFontSize == nil)
                }
            }
            Text("The quick brown fox jumps over the lazy dog.")
                .font(.system(size: model.preferences.scriptFont)).lineLimit(1).truncationMode(.tail)
                .accessibilityLabel("Font size preview")
        }
    }
}

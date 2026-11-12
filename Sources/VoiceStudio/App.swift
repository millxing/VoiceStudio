import AppKit
import Combine
import SwiftUI

final class StudioMenuState: ObservableObject {
    @Published var canGenerate = false
    @Published var hasScripts = false
    @Published var hasSelectedScripts = false
    @Published var canStop = false
    @Published var canPlay = false
    @Published var hasTake = false
    @Published var canResume = false
    @Published var inEditor = false
    @Published var hasClip = false
    @Published var hasTimeline = false
    @Published var canAddTake = false
    func update(_ model: AppModel) {
        inEditor = model.sidebar == .editor
        hasClip = inEditor && model.selectedClip != nil
        hasTimeline = !model.timeline.isEmpty
        canAddTake = model.editorTakes.contains { model.selectedTakes.contains($0.id) }
        canGenerate = model.canGenerate
        hasSelectedScripts = model.sidebar == .scripts && !model.selectedScripts.isEmpty
        hasScripts = model.scripts.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        canStop = model.queueRunning
        canPlay = model.take?.status == .completed
        hasTake = model.take != nil
        canResume = model.queuedCount > 0 && !model.queueRunning
    }
}
@main
struct VoiceStudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()
    @StateObject private var menu = StudioMenuState()
    var body: some Scene {
        Window("VoiceStudio", id: "main") {
            ContentView()
                .environment(model).themed()
                .overlay { if GridOverlay.enabled { GridOverlay() } }
                .frame(minWidth: 1080, minHeight: 720)
                .onChange(of: model.library, initial: true) { menu.update(model) }
                .onChange(of: model.selectedScripts) { menu.update(model) }
                .onChange(of: model.selectedTakes) { menu.update(model) }
                .onChange(of: model.queueRunning) { menu.update(model) }
                .onChange(of: model.sidebar) { menu.update(model) }
                .onChange(of: model.selectedClips) { menu.update(model) }
                .task { delegate.model = model }
        }
        .defaultLaunchBehavior(.presented)
        .defaultSize(width: 1240, height: 820)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
            ToolbarCommands()
            CommandGroup(replacing: .newItem) {
                Button("New Script") { model.addScript() }.keyboardShortcut("n")
                Button("Import Audio Clips…") { model.sidebar = .editor; model.importAudio(undo: NSApp.keyWindow?.undoManager) }
                Button("Import Text Files…") { model.importScripts() }.keyboardShortcut("o")
                Button("Add Voice…") { model.addVoice() }.keyboardShortcut("v", modifiers: [.command, .shift])
            }
            CommandGroup(after: .pasteboard) {
                Divider()
                // ⌘D duplicates scripts. In a text field it does nothing else, so the shortcut is safe there.
                Button("Duplicate Selected Scripts") { model.duplicateScripts(model.selectedScripts, undo: NSApp.keyWindow?.undoManager) }
                    .keyboardShortcut("d").disabled(!menu.hasSelectedScripts)
            }
            CommandMenu("Speech") {
                Button("Install Speech Engine…") { model.showingEngineSetup = true }.keyboardShortcut("i", modifiers: [.command, .option])
                    .disabled(model.queueRunning)
                Divider()
                Button("Generate Selected") { model.queue() }.keyboardShortcut("g").disabled(!menu.canGenerate)
                Button("Generate All") { model.queue(all: true) }.keyboardShortcut("g", modifiers: [.command, .shift]).disabled(!menu.hasScripts)
                Divider()
                Button("Stop Queue") { model.stopQueue() }.keyboardShortcut(".").disabled(!menu.canStop)
                Button("Resume Queue") { model.resumeQueue() }.disabled(!menu.canResume)
            }
            CommandMenu("Playback") {
                // In the editor, Play/Pause plays the timeline; elsewhere, the selected take.
                Button("Play/Pause") {
                    if menu.inEditor { model.toggleTimelinePlayback() } else if let take = model.take { model.play(take) }
                }
                .keyboardShortcut("p", modifiers: [.command, .option]).disabled(menu.inEditor ? !menu.hasTimeline : !menu.canPlay)
                Toggle("Loop Playback", isOn: Binding(
                    get: { menu.inEditor ? model.timelineLoopEnabled : model.playback.loops },
                    set: { if menu.inEditor { model.setTimelineLoopEnabled($0, undo: NSApp.keyWindow?.undoManager) } else { model.playback.loops = $0 } }))
                    .keyboardShortcut("l")
                Divider()
                Button("Export Clip…") { if let take = model.take { model.export(take) } }
                    .keyboardShortcut("e", modifiers: [.command, .shift]).disabled(!menu.canPlay)
                Button("Show in Finder") { if let take = model.take { model.reveal(take) } }
                    .keyboardShortcut("r", modifiers: [.command, .shift]).disabled(!menu.canPlay)
            }
            CommandMenu("Editor") {
                Button("Save Timeline…") { model.saveTimeline() }.keyboardShortcut("s", modifiers: [.command, .shift])
                Button("Load Timeline…") { model.loadTimeline(undo: NSApp.keyWindow?.undoManager) }.keyboardShortcut("o", modifiers: [.command, .shift])
                Divider()
                Button("Add Selected Clips to Timeline") { model.addTakesToTimeline(model.selectedTakes, track: 0, undo: NSApp.keyWindow?.undoManager) }
                    .keyboardShortcut("a", modifiers: [.command, .shift]).disabled(!menu.canAddTake)
                Divider()
                Button("Split at Playhead") { model.splitAtPlayhead(undo: NSApp.keyWindow?.undoManager) }
                    .keyboardShortcut("b").disabled(!menu.inEditor || !menu.hasTimeline)
                Button("Delete Selected Clips") { model.deleteClip(ripple: false, undo: NSApp.keyWindow?.undoManager) }
                    .disabled(!menu.hasClip)
                Button("Ripple Delete Selected Clips") { model.deleteClip(ripple: true, undo: NSApp.keyWindow?.undoManager) }
                    .disabled(!menu.hasClip)
                Button("Go to Start") { model.seekTimeline(0) }
                    .keyboardShortcut(.home, modifiers: []).disabled(!menu.inEditor)
                Divider()
                Button("Zoom In") { model.zoom(by: 1.5) }.keyboardShortcut("=").disabled(!menu.inEditor)
                Button("Zoom Out") { model.zoom(by: 1 / 1.5) }.keyboardShortcut("-").disabled(!menu.inEditor)
                Divider()
                Button("Export Timeline as WAV…") { model.exportTimeline(.wav) }
                    .keyboardShortcut("e", modifiers: [.command, .option]).disabled(!menu.hasTimeline)
                Button("Export Timeline as MP3…") { model.exportTimeline(.mp3) }
                    .keyboardShortcut("e", modifiers: [.command, .option, .shift]).disabled(!menu.hasTimeline)
                Divider()
                Button("Clear Timeline…") { model.confirmClearTimeline(undo: NSApp.keyWindow?.undoManager) }
                    .keyboardShortcut(.delete, modifiers: [.command, .option]).disabled(!menu.inEditor || !menu.hasTimeline)
            }
        }
        Settings { SettingsView().environment(model).themed() }.windowResizability(.contentSize)
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    private var quittingAfterInstallation = false
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Self-tests run as a background app: no Dock icon, no menu bar, and macOS does not
        // bring it forward at launch, so the person at the Mac keeps their focus.
        guard SelfTest.requested else { return }
        NSApp.setActivationPolicy(.accessory)
        // SwiftUI still activates the app when it presents the window. Hand focus straight back
        // to whatever the person was using, every time.
        let previous = NSWorkspace.shared.frontmostApplication
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                guard let previous, !previous.isTerminated else { NSApp.deactivate(); return }
                NSApp.yieldActivation(to: previous)
                previous.activate()
            }
        }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !SelfTest.requested else { return }
        NSApp.setActivationPolicy(.regular); NSApp.activate()
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, model.installer.running else { return .terminateNow }
        if !quittingAfterInstallation {
            quittingAfterInstallation = true
            model.installer.cancel()
            Task {
                while model.installer.running { try? await Task.sleep(for: .milliseconds(100)) }
                NSApp.terminate(nil)
            }
        }
        // Return to the normal event loop while cancellation finishes. AppKit's
        // terminateLater nested loop can block the installer's main-actor work.
        return .terminateCancel
    }
    func applicationWillTerminate(_ notification: Notification) {
        model?.shutdown()
        if SelfTest.requested { exit(SelfTest.exitCode) }
    }
}

import AppKit
import Combine
import SwiftUI

final class StudioMenuState: ObservableObject {
    @Published var canGenerate = false
    @Published var hasScripts = false
    @Published var canStop = false
    @Published var canPlay = false
    @Published var hasTake = false
    @Published var canResume = false
    func update(_ model: AppModel) {
        canGenerate = model.canGenerate
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
                .onChange(of: model.selectedTake) { menu.update(model) }
                .onChange(of: model.queueRunning) { menu.update(model) }
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
                Button("Import Text Files…") { model.importScripts() }.keyboardShortcut("o")
                Button("Add Voice…") { model.addVoice() }.keyboardShortcut("v", modifiers: [.command, .shift])
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
                Button("Play/Pause") { if let take = model.take { model.play(take) } }
                    .keyboardShortcut("p", modifiers: [.command, .option]).disabled(!menu.canPlay)
                Button("Export Take…") { if let take = model.take { model.export(take) } }
                    .keyboardShortcut("e", modifiers: [.command, .shift]).disabled(!menu.canPlay)
                Button("Show in Finder") { if let take = model.take { model.reveal(take) } }
                    .keyboardShortcut("r", modifiers: [.command, .shift]).disabled(!menu.canPlay)
            }
        }
        Settings { SettingsView().environment(model).themed() }.windowResizability(.contentSize)
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    private var quittingAfterInstallation = false
    func applicationDidFinishLaunching(_ notification: Notification) {
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

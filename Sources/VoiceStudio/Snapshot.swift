import AppKit
import IOKit.pwr_mgt
import SwiftUI

/// Screenshot mode for agents.
///   APP_STORE=/tmp/test.store APP_SNAPSHOT=/tmp/shots /Applications/VoiceStudio.app/Contents/MacOS/VoiceStudio
/// writes <page>-light.png and <page>-dark.png for every sidebar page, and
/// settings-<tab>-light.png and settings-<tab>-dark.png for every Settings tab, then quits.
/// Each PNG gets a <page>-<mode>-layout.json with the grid probes (tools/check-layout.swift).
/// APP_SNAPSHOT_PAGES=all,starred limits the pages. Add "settings" to include Settings.
/// Add APP_ACCENT=<id> to see the pages in another accent.
enum Snapshot {
    static func runIfRequested(model: AppModel, openSettings: OpenSettingsAction) {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["APP_SNAPSHOT"], !dir.isEmpty else { return }
        // Snapshots never run against the real database.
        guard Store.isOverridden else {
            print("SNAPSHOT refused: set APP_STORE to a file in /tmp")
            NSApp.terminate(nil)
            return
        }
        let only = env["APP_SNAPSHOT_PAGES"].map { Set($0.split(separator: ",").map(String.init)) }
        Task {
            // A sleeping display gives screencapture nothing. Declaring user
            // activity wakes it; the assertion keeps it on until the run quits.
            var activity: IOPMAssertionID = 0
            IOPMAssertionDeclareUserActivity("Snapshots" as CFString, kIOPMUserActiveLocal, &activity)
            var awake: IOPMAssertionID = 0
            IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                        IOPMAssertionLevel(kIOPMAssertionLevelOn), "Snapshots" as CFString, &awake)
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? await Task.sleep(for: .seconds(1.5))
            for mode in ["light", "dark"] {
                NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                ThemeStore.shared.mode = mode == "light" ? .light : .dark
                for page in SidebarItem.allCases where only?.contains(page.rawValue) ?? true {
                    model.sidebar = page
                    try? await Task.sleep(for: .seconds(0.4))
                    // Lists may clear their selection when their page leaves.
                    // Seed snapshots explicitly select an existing row.
                    if page == .voices { model.selectedVoice = model.voices.first?.id }
                    if page == .takes { model.selectedTake = model.takes.first?.id }
                    if page == .scripts, model.selectedScripts.isEmpty, let script = model.scripts.first {
                        model.selectedScripts = [script.id]
                    }
                    if env["APP_SNAPSHOT_MULTI"] == "1" {
                        if page == .scripts { model.selectedScripts = Set(model.scripts.prefix(2).map(\.id)) }
                        if page == .takes || page == .editor { model.selectedTakes = Set(model.editorTakes.prefix(2).map(\.id)) }
                        if page == .editor { model.selectedClips = Set(model.timeline.clips.prefix(2).map(\.id)) }
                    }
                    try? await Task.sleep(for: .seconds(0.4))
                    await capture(to: "\(dir)/\(page.rawValue)-\(mode).png")
                }
                if (only == nil || only?.contains("cached-voice") == true), let cached = model.voices.first(where: { $0.cachedFile != nil }) {
                    model.sidebar = .voices; model.selectedVoice = cached.id
                    try? await Task.sleep(for: .seconds(0.5))
                    await capture(to: "\(dir)/cached-voice-\(mode).png")
                    model.editingVoice = cached; model.showingVoiceSheet = true
                    try? await Task.sleep(for: .seconds(0.5))
                    let cachedSheet = NSApp.windows.first(where: { $0.attachedSheet != nil })?.attachedSheet
                    await capture(to: "\(dir)/edit-cached-voice-\(mode).png", window: cachedSheet)
                    model.showingVoiceSheet = false
                    try? await Task.sleep(for: .seconds(0.3))
                }
                if only == nil || only?.contains("setup") == true {
                    model.showingEngineSetup = true
                    try? await Task.sleep(for: .seconds(0.5))
                    let sheet = NSApp.windows.first(where: { $0.attachedSheet != nil })?.attachedSheet
                    await capture(to: "\(dir)/setup-\(mode).png", window: sheet)
                    model.showingEngineSetup = false
                    try? await Task.sleep(for: .seconds(0.3))
                }
                if only == nil || only?.contains("add-voice") == true {
                    model.editingVoice = nil; model.showingVoiceSheet = true
                    try? await Task.sleep(for: .seconds(0.5))
                    let sheet = NSApp.windows.first(where: { $0.attachedSheet != nil })?.attachedSheet
                    await capture(to: "\(dir)/add-voice-\(mode).png", window: sheet)
                    model.showingVoiceSheet = false
                    try? await Task.sleep(for: .seconds(0.3))
                }
            }
            if only == nil || only?.contains("settings") == true {
                let main = NSApp.windows.first { $0.canBecomeMain && !$0.isSheet }
                openSettings()
                try? await Task.sleep(for: .seconds(1))
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                ThemeStore.shared.mode = mode == "light" ? .light : .dark
                    for tab in SettingsTab.allCases {
                        model.settingsTab = tab
                        try? await Task.sleep(for: .seconds(0.8))
                        let settings = NSApp.windows.first { $0.isVisible && $0 !== main && !$0.isSheet }
                        await capture(to: "\(dir)/settings-\(tab.rawValue)-\(mode).png", window: settings)
                    }
                }
            }
            print("SNAPSHOT done \(dir)")
            // An open sheet refuses terminate, and the run would wait forever.
            for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
            NSApp.terminate(nil)
        }
    }

    /// Captures the real window with screencapture, so glass, sidebars, and
    /// materials look exactly as on screen. That needs Screen Recording
    /// permission for the app that started this one (your terminal, or Claude).
    /// Without it, falls back to drawing the view hierarchy, which leaves
    /// sidebars and glass blank.
    private static func capture(to path: String, window: NSWindow? = nil) async {
        // Another app can hide this one while snapshots run (computer use hides
        // apps it does not control). Hidden windows cannot be captured.
        if NSApp.isHidden { NSApp.unhideWithoutActivation() }
        guard let window = window ?? NSApp.windows.first(where: { $0.canBecomeMain && !$0.isSheet }) else {
            print("SNAPSHOT no window")
            return
        }
        // Active, like a window someone is using: real accent colors and focus rings.
        // Activation is asynchronous. Wait for the actual key-window state
        // before capturing, so the first image cannot be an inactive window.
        for _ in 0..<10 {
            // Snapshot-only activation: cooperative activate() can be refused
            // while the terminal/agent remains frontmost. This API is still
            // supported by the macOS 26 SDK and is confined to /tmp test runs.
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .milliseconds(200))
            if NSApp.isActive && window.isKeyWindow { break }
        }
        guard NSApp.isActive && window.isKeyWindow else {
            print("SNAPSHOT refused inactive window \(path)")
            return
        }
        let size = window.contentView?.bounds.size ?? .zero
        GridProbes.shared.write(to: path.replacingOccurrences(of: ".png", with: "-layout.json"), window: size)
        try? FileManager.default.removeItem(atPath: path)
        // The first capture of a run sometimes misses the window. Try three times.
        for _ in 1...3 {
            let shot = Process()
            shot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            shot.arguments = ["-x", "-o", "-l", String(window.windowNumber), path]
            try? shot.run()
            shot.waitUntilExit()
            if FileManager.default.fileExists(atPath: path) {
                print("SNAPSHOT \(path)")
                return
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
            print("SNAPSHOT \(path) (fallback: no Screen Recording permission, sidebars and glass are blank)")
        }
    }
}

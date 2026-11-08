import Foundation
import VoiceStudioKit

enum SeedData {
    static func insertIfRequested(into model: AppModel) {
        guard ProcessInfo.processInfo.environment["APP_SEED"] == "1", Store.isOverridden, model.scripts.isEmpty else { return }
        let samples = [
            ScriptDocument(title: "A quiet morning", text: "The morning light filled the room as I opened the window. Outside, the city was beginning to wake up, and somewhere in the distance a train was passing."),
            ScriptDocument(title: "Chapter one — The arrival", text: "The station was almost empty when she arrived. A single suitcase rested beside the bench, and the clock above the platform had stopped at a quarter past three."),
            ScriptDocument(title: "Opening narration", text: "Some stories begin with a question. This one began with a letter, folded twice and left on the kitchen table."),
            ScriptDocument(title: "An alternate ending", text: "At last, the lights came on. For the first time in years, the old house felt like home.")
        ]
        model.library.scripts = samples
        model.selectedScripts = [samples[0].id]
        let sample = Bundle.main.resourceURL?.appending(path: "demo-reference.wav")
        if let sample, FileManager.default.fileExists(atPath: sample.path) {
            try? model.storeVoice(name: "Narrator", urls: [sample], existing: nil)
            model.selectedVoice = model.voices.first?.id
        }
        if let fixture = ProcessInfo.processInfo.environment["APP_CACHE_FIXTURE"] {
            let file = "Voices/ImportedNarrator.pth"
            let target = Store.root.appending(path: file)
            do {
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: URL(fileURLWithPath: fixture), to: target)
                model.library.voices.append(VoiceReference(name: "Imported narrator", files: [], cachedFile: file))
            } catch { model.message = "Unable to seed cached voice: \(error.localizedDescription)" }
        }
        model.preferences.voice = "builtin:Craig Gutsy"
        model.sidebar = .scripts
        for index in 1...3 {
            var take = SpeechTake(script: samples[0], voiceName: "Craig Gutsy", speaker: "Craig Gutsy", references: [], language: "en", speed: 1, seed: 1234 + index, modelFolder: "", device: "mps", number: index)
            if let sample {
                let target = Store.root.appending(path: take.audioFile)
                try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? FileManager.default.copyItem(at: sample, to: target)
                take.status = .completed; take.duration = 9.505; take.generationSeconds = 1.67
            }
            model.library.takes.append(take)
        }
        model.selectedTake = model.library.takes.first?.id
    }
}

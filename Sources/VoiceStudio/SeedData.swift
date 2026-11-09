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
            let target = take.audioURL(relativeTo: Store.root)
            try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let sample, FileManager.default.fileExists(atPath: sample.path) {
                try? FileManager.default.copyItem(at: sample, to: target)
                take.duration = 9.505
            } else {
                // No bundled recording: a synthetic, speech-shaped signal keeps the editor's waveforms realistic.
                let audio = speechLike(seconds: 4 + Double(index) * 1.5, seed: UInt64(index))
                try? TimelineAudio.writeWAV(audio, to: target)
                take.duration = Double(audio.count) / TimelineAudio.sampleRate
            }
            take.status = .completed; take.generationSeconds = 1.67
            model.library.takes.append(take)
        }
        model.selectedTake = model.library.takes.first?.id
        let seeded = model.library.takes
        var timeline = Timeline()
        timeline.add(takeID: seeded[0].id, duration: seeded[0].duration, track: 0, at: 0.5)
        if let cut = timeline.clips.first { timeline.split(cut.id, at: 3); timeline.trimStart(timeline.clips[1].id, to: 3.6) }
        timeline.add(takeID: seeded[1].id, duration: seeded[1].duration, track: 0)
        timeline.add(takeID: seeded[2].id, duration: seeded[2].duration, track: 1, at: 2)
        timeline.add(takeID: seeded[0].id, duration: seeded[0].duration, track: 2, at: 9)
        timeline.tracks[2].volume = 0.6
        model.library.timeline = timeline
    }
    /// Bursts of filtered noise and voiced tone with pauses, roughly like syllables and words.
    static func speechLike(seconds: Double, seed: UInt64) -> [Float] {
        var state = seed &* 6364136223846793005 &+ 1442695040888963407
        func random() -> Float { state = state &* 6364136223846793005 &+ 1442695040888963407; return Float(state >> 40) / Float(1 << 24) }
        let rate = TimelineAudio.sampleRate
        var out = [Float](repeating: 0, count: Int(seconds * rate))
        var t = 0.15
        while t < seconds - 0.3 {
            let word = 0.15 + Double(random()) * 0.45
            let pitch = 110 + Double(random()) * 60
            let start = Int(t * rate), length = Int(word * rate)
            let syllables = Double(1 + Int(random() * 3))
            var smooth: Float = 0
            for n in 0..<length where start + n < out.count {
                let phase = Double(n) / Double(length)
                let envelope = Float(sin(phase * .pi)) * Float(0.55 + 0.45 * abs(sin(phase * .pi * syllables)))
                smooth = smooth * 0.9 + (random() - 0.5) * 0.1
                let voiced = Float(sin(2 * .pi * pitch * Double(n) / rate))
                out[start + n] = (voiced * 0.35 + smooth * 3) * envelope * 0.7
            }
            t += word + 0.05 + Double(random()) * (random() > 0.75 ? 0.5 : 0.12)
        }
        return out
    }
}

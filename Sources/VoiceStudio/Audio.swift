import AppKit
import AVFoundation
import Observation
import VoiceStudioKit

@Observable
final class AudioPlayback {
    var url: URL?
    var isPlaying = false
    var position = 0.0
    var duration = 0.0
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var timer: Timer?
    /// Repeats the current audio until paused. Applies to takes and the editor timeline.
    var loops = false { didSet { player?.numberOfLoops = loops ? -1 : 0 } }
    func toggle(_ url: URL) throws {
        if self.url == url, let player {
            if player.isPlaying { player.pause(); isPlaying = false; position = player.currentTime; stopClock() }
            else { if player.currentTime >= player.duration { player.currentTime = 0 }; player.play(); isPlaying = true; startClock() }
            return
        }
        try start(url)
    }
    /// Starts `url` from `time`, replacing whatever was playing.
    func start(_ url: URL, at time: Double = 0) throws {
        stop()
        player = try AVAudioPlayer(contentsOf: url)
        guard let player, player.prepareToPlay() else { throw LibraryFile.failure("This audio file could not be opened.") }
        player.numberOfLoops = loops ? -1 : 0
        player.currentTime = min(max(0, time), max(0, player.duration - 0.01))
        guard player.play() else { throw LibraryFile.failure("This audio file could not be played.") }
        self.url = url; duration = player.duration; position = player.currentTime; isPlaying = true
        startClock()
    }
    /// Moves `position` while audio plays. The clock stops when the audio stops:
    /// every tick redraws the window, and constant redraws stop macOS from showing tooltips.
    private func startClock() {
        timer?.invalidate()
        timer = Timer(timeInterval: 1.0 / 30, repeats: true) { @Sendable [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let player = self.player else { return }
                if self.position != player.currentTime { self.position = player.currentTime }
                if !player.isPlaying { self.isPlaying = false; self.stopClock() }
            }
        }
        // Keep the UI clock moving while AppKit tracks mouse presses and drags.
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }
    /// True while the position clock ticks. Only while audio plays.
    var clockRunning: Bool { timer != nil }
    private func stopClock() { timer?.invalidate(); timer = nil }
    /// Pauses or resumes whatever is loaded.
    func toggle() { if let url { try? toggle(url) } }
    func seek(_ value: Double) { player?.currentTime = value; position = value }
    func stop() { player?.stop(); player = nil; stopClock(); url = nil; isPlaying = false; position = 0; duration = 0 }
}
enum AudioValidation {
    static func validate(_ url: URL) throws -> Double {
        let file = try AVAudioFile(forReading: url)
        guard file.length > 0, file.processingFormat.sampleRate > 0 else { throw LibraryFile.failure("\(url.lastPathComponent) contains no readable audio.") }
        return Double(file.length) / file.processingFormat.sampleRate
    }
}
@Observable
final class VoiceRecorder {
    var recording = false
    var started = Date()
    var error = ""
    var temporaryURL: URL?
    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var canceled = false
    func start() async {
        error = ""
        let permitted = await AVCaptureDevice.requestAccess(for: .audio)
        guard !canceled else { return }
        guard permitted else { error = "Microphone access is off. Enable VoiceStudio in System Settings > Privacy & Security > Microphone."; return }
        do {
            let url = FileManager.default.temporaryDirectory.appending(path: "VoiceStudio-\(UUID().uuidString).wav")
            temporaryURL = url
            recorder = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 24000, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false])
            guard recorder?.record() == true else { throw LibraryFile.failure("Unable to start recording. Check your microphone input.") }
            started = Date(); recording = true
        } catch { self.error = error.localizedDescription }
    }
    func cancel() { canceled = true; _ = stop() }
    func stop() -> URL? { recorder?.stop(); recorder = nil; recording = false; return temporaryURL }
}
/// Minutes, seconds, and tenths, for the editor: 1:04.2
func preciseTimeLabel(_ seconds: Double) -> String {
    let tenths = max(0, Int((seconds * 10).rounded(.down)))
    return String(format: "%d:%02d.%d", tenths / 600, (tenths / 10) % 60, tenths % 10)
}
func timeLabel(_ seconds: Double) -> String {
    let value = max(0, Int(seconds))
    return String(format: "%d:%02d", value / 60, value % 60)
}

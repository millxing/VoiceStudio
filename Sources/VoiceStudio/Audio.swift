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
    func toggle(_ url: URL) throws {
        if self.url == url, let player {
            if player.isPlaying { player.pause(); isPlaying = false }
            else { if player.currentTime >= player.duration { player.currentTime = 0 }; player.play(); isPlaying = true }
            return
        }
        stop()
        player = try AVAudioPlayer(contentsOf: url)
        guard let player, player.prepareToPlay(), player.play() else { throw LibraryFile.failure("This audio file could not be opened.") }
        self.url = url; duration = player.duration; isPlaying = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { @Sendable [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let player = self.player else { return }
                self.position = player.currentTime; self.isPlaying = player.isPlaying
            }
        }
    }
    func seek(_ value: Double) { player?.currentTime = value; position = value }
    func stop() { player?.stop(); player = nil; timer?.invalidate(); timer = nil; url = nil; isPlaying = false; position = 0; duration = 0 }
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
func timeLabel(_ seconds: Double) -> String {
    let value = max(0, Int(seconds))
    return String(format: "%d:%02d", value / 60, value % 60)
}

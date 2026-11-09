import AVFoundation
import Foundation
import VoiceStudioKit

/// Audio file work for the editor: decoding takes, waveform peaks, and writing the mix.
/// Everything is mono at one sample rate, so clips from any take line up sample for sample.
enum TimelineAudio {
    nonisolated static let sampleRate = 24_000.0
    /// Waveform resolution: one peak per this many seconds.
    nonisolated static let peakInterval = 0.01

    /// Reads a file as mono Float32 at `sampleRate`, converting rate and channels when needed.
    nonisolated static func samples(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let source = file.processingFormat
        guard file.length > 0, let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(file.length)) else { return [] }
        try file.read(into: input)
        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false) else { return [] }
        if source.sampleRate == sampleRate, source.channelCount == 1, source.commonFormat == .pcmFormatFloat32, let data = input.floatChannelData {
            return Array(UnsafeBufferPointer(start: data[0], count: Int(input.frameLength)))
        }
        guard let converter = AVAudioConverter(from: source, to: target) else { throw LibraryFile.failure("\(url.lastPathComponent) uses an audio format the editor cannot convert.") }
        converter.downmix = true
        let capacity = AVAudioFrameCount(Double(input.frameLength) * sampleRate / source.sampleRate) + 4096
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return [] }
        let feeder = Feeder(input)
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, state in feeder.next(state) }
        if status == .error { throw error ?? LibraryFile.failure("\(url.lastPathComponent) could not be converted.") }
        guard let data = output.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: data[0], count: Int(output.frameLength)))
    }
    /// Hands the converter its single input buffer once, then reports the end of the stream.
    private nonisolated final class Feeder: @unchecked Sendable {
        let buffer: AVAudioPCMBuffer
        var given = false
        init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }
        func next(_ state: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
            if given { state.pointee = .endOfStream; return nil }
            given = true; state.pointee = .haveData; return buffer
        }
    }

    /// The loudest sample in each `peakInterval` window, for drawing waveforms.
    nonisolated static func peaks(_ samples: [Float]) -> [Float] {
        let window = max(1, Int(sampleRate * peakInterval))
        return stride(from: 0, to: samples.count, by: window).map { start in
            samples[start..<min(samples.count, start + window)].reduce(0) { max($0, abs($1)) }
        }
    }

    /// Writes mono samples as a 16-bit PCM WAV file.
    nonisolated static func writeWAV(_ samples: [Float], to url: URL) throws {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(1, samples.count))),
              let data = buffer.floatChannelData else { throw LibraryFile.failure("Unable to prepare audio for writing.") }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { data[0].update(from: $0.baseAddress!, count: samples.count) }
        try? FileManager.default.removeItem(at: url)
        let file = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false],
            commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)
        file.close()
    }

    /// macOS has no MP3 encoder, so MP3 export uses LAME or FFmpeg when either is installed.
    nonisolated static var mp3Encoder: URL? {
        ["/opt/homebrew/bin/lame", "/usr/local/bin/lame", "/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/lame"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }
    nonisolated static func encodeMP3(wav: URL, to destination: URL) throws {
        guard let encoder = mp3Encoder else {
            throw LibraryFile.failure("MP3 export needs LAME or FFmpeg. Install one with Homebrew (brew install lame), or export as WAV.")
        }
        let process = Process()
        process.executableURL = encoder
        process.arguments = encoder.lastPathComponent == "lame"
            ? ["--quiet", "-b", "192", wav.path, destination.path]
            : ["-y", "-loglevel", "error", "-i", wav.path, "-codec:a", "libmp3lame", "-b:a", "192k", destination.path]
        let errors = Pipe()
        process.standardError = errors; process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw LibraryFile.failure("MP3 encoding failed. \(detail.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }
}

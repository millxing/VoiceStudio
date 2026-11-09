import Foundation
import VoiceStudioKit

import Observation

@Observable
final class SpeechEngine {
    var status = "Engine stopped"
    var isReady = false
    var isStarting = false
    var speakers = ["Craig Gutsy", "Ana Florence", "Daisy Studious"]
    var languages = [String]()
    var lastError = ""
    @ObservationIgnored var onEvent: (([String: Any]) -> Void)?
    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var input: FileHandle?
    @ObservationIgnored private var reader: Task<Void, Never>?
    @ObservationIgnored private var logHandle: FileHandle?
    @ObservationIgnored private var token = UUID()
    @ObservationIgnored private(set) var configuration = ""

    func start(python: String, device: String, modelFolder: String, log: URL) {
        stop()
        lastError = ""
        guard FileManager.default.isExecutableFile(atPath: python) else {
            fail("Python was not found. Choose Speech > Install Speech Engine, or select a compatible interpreter in Settings > Engine.")
            return
        }
        guard let script = Bundle.main.resourceURL?.appending(path: "worker.py"), FileManager.default.fileExists(atPath: script.path) else {
            fail("The app's XTTS worker is missing. Rebuild VoiceStudio."); return
        }
        let proc = Process(), stdin = Pipe(), stdout = Pipe()
        try? FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let logging = try? FileHandle(forWritingTo: log)
        logHandle = logging
        proc.executableURL = URL(fileURLWithPath: python)
        proc.arguments = ["-B", "-u", script.path, device, modelFolder]
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        env["TOKENIZERS_PARALLELISM"] = "false"
        // Strict MPS: an inherited shell fallback setting must not hide failures.
        env.removeValue(forKey: "PYTORCH_ENABLE_MPS_FALLBACK")
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        proc.environment = env
        proc.standardInput = stdin; proc.standardOutput = stdout; proc.standardError = logging ?? FileHandle.nullDevice
        process = proc; input = stdin.fileHandleForWriting
        let generation = token
        proc.terminationHandler = { @Sendable [weak self] process in
            let code = process.terminationStatus
            Task { @MainActor [weak self] in
                guard let self, self.token == generation else { return }
                if self.lastError.isEmpty { self.fail("The speech engine stopped (exit \(code)). Check Engine Log in Settings, then restart.") }
            }
        }
        do {
            try proc.run()
            configuration = "\(python)|\(device)|\(modelFolder)"
            isStarting = true; status = "Starting XTTS…"
            reader = Task { [weak self] in
                do {
                    for try await line in stdout.fileHandleForReading.bytes.lines {
                        guard !Task.isCancelled, let self, self.token == generation else { return }
                        if let data = line.data(using: .utf8), let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            self.receive(event)
                        }
                    }
                } catch {
                    guard let self, self.token == generation else { return }
                    self.fail("Unable to read the speech engine: \(error.localizedDescription)")
                }
            }
        } catch { fail("Unable to start Python: \(error.localizedDescription)") }
    }
    private func receive(_ event: [String: Any]) {
        switch event["event"] as? String {
        case "ready":
            isReady = true; isStarting = false
            speakers = (event["speakers"] as? [String] ?? []).sorted()
            languages = event["languages"] as? [String] ?? []
            status = (event["device"] as? String == "mps") ? "Apple GPU ready" : "CPU ready"
        case "status": status = event["message"] as? String ?? "Loading…"
        case "fatal": fail(event["message"] as? String ?? "Unable to load XTTS."); return
        default: break
        }
        onEvent?(event)
    }
    func send(_ request: [String: Any]) throws {
        guard let input, isReady else { throw LibraryFile.failure("The speech engine is not ready.") }
        var data = try JSONSerialization.data(withJSONObject: request)
        data.append(10)
        try input.write(contentsOf: data)
    }
    func stop() {
        token = UUID(); reader?.cancel(); reader = nil
        if let proc = process, proc.isRunning { proc.terminate() }
        try? input?.close(); input = nil; process = nil
        try? logHandle?.close(); logHandle = nil
        isReady = false; isStarting = false; status = "Engine stopped"; configuration = ""
    }
    private func fail(_ message: String) {
        isReady = false; isStarting = false; status = "Engine unavailable"; lastError = message
        onEvent?(["event": "engineError", "message": message])
    }
}

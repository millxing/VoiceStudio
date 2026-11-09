import AppKit
import CryptoKit
import Darwin
import Foundation
import Observation
import SwiftUI

@Observable
final class EngineInstaller {
    var running = false
    var status = "Install the local speech engine"
    var details = ""
    var error = ""
    var completed = false
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var process: Process?
    let root = Store.root.appending(path: "SpeechEngine", directoryHint: .isDirectory)
    var python: URL { root.appending(path: "Runtime/bin/python") }
    var receipt: [String: String]? {
        guard let data = try? Data(contentsOf: root.appending(path: "receipt.json")),
              let values = try? JSONDecoder().decode([String: String].self, from: data),
              values["python"] == python.path,
              FileManager.default.isExecutableFile(atPath: python.path),
              let folder = values["modelFolder"],
              ["model.pth", "config.json", "vocab.json"].allSatisfy({ FileManager.default.fileExists(atPath: folder + "/" + $0) }) else { return nil }
        return values
    }
    func install(accepted: Bool, success: @escaping () -> Void) {
        guard accepted, !running else { return }
        running = true; completed = false; error = ""; details = ""
        task = Task {
            do {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                let license = Bundle.main.resourceURL!.appending(path: "XTTS-MODEL-LICENSE.txt")
                let agreement: [String: String] = ["acceptedAt": Date().ISO8601Format(), "licenseSHA256": SHA256.hash(data: try Data(contentsOf: license)).map { String(format: "%02x", $0) }.joined()]
                try JSONEncoder().encode(agreement).write(to: root.appending(path: "license-acceptance.json"), options: .atomic)
                status = "Downloading installation tools…"
                let tools = root.appending(path: "Tools", directoryHint: .isDirectory)
                try FileManager.default.createDirectory(at: tools, withIntermediateDirectories: true)
                let uv = tools.appending(path: "uv-aarch64-apple-darwin/uv")
                // Verify the archive on every run; never trust an interrupted bootstrap.
                let url = URL(string: "https://github.com/astral-sh/uv/releases/download/0.11.31/uv-aarch64-apple-darwin.tar.gz")!
                let (download, response) = try await URLSession.shared.download(from: url)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw InstallError.message("Could not download uv. Check the internet connection and retry.") }
                let digest = SHA256.hash(data: try Data(contentsOf: download)).map { String(format: "%02x", $0) }.joined()
                guard digest == "b2b93e82a6786f9c7cb89fd4ca0e859a147b292ae8f6f95784f9742f0efec39e" else { throw InstallError.message("The installation tool failed its integrity check.") }
                try Task.checkCancellation()
                try await run("/usr/bin/tar", ["-xzf", download.path, "-C", tools.path])
                try? FileManager.default.removeItem(at: download)
                status = "Installing Python 3.12…"
                try await run(uv.path, ["python", "install", "3.12", "--no-bin", "--no-progress"])
                try await run(uv.path, ["venv", "--python", "3.12", "--allow-existing", root.appending(path: "Runtime").path])
                status = "Installing speech engine packages…"
                let resources = Bundle.main.resourceURL!
                try await run(uv.path, ["pip", "install", "--python", python.path, "-r", resources.appending(path: "requirements.lock.txt").path, "--no-progress"])
                status = "Downloading and checking XTTS-v2…"
                try await run(python.path, ["-B", "-u", resources.appending(path: "install_engine.py").path, root.path, "--accept-cpml"])
                try Task.checkCancellation()
                guard receipt != nil else { throw InstallError.message("The speech engine check did not complete. Retry installation.") }
                status = "Speech engine ready"; completed = true; success()
            } catch {
                self.error = Task.isCancelled ? "Installation cancelled. Downloaded files are kept for retry." : error.localizedDescription
                status = "Installation stopped"
            }
            running = false; process = nil; task = nil
        }
    }
    func cancel() {
        task?.cancel()
        guard let child = process, child.isRunning else { return }
        child.interrupt()
        Task {
            try? await Task.sleep(for: .seconds(2))
            if child.isRunning { child.terminate() }
            try? await Task.sleep(for: .seconds(2))
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
        }
    }
    private func run(_ executable: String, _ arguments: [String]) async throws {
        try Task.checkCancellation()
        let child = Process(), pipe = Pipe()
        child.executableURL = URL(fileURLWithPath: executable); child.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        for key in Array(env.keys) where key.hasPrefix("UV_") { env.removeValue(forKey: key) }
        env["UV_NO_CONFIG"] = "1"
        env["UV_PYTHON_INSTALL_DIR"] = root.appending(path: "Python").path
        env["UV_CACHE_DIR"] = root.appending(path: "Cache").path
        env["UV_PYTHON_PREFERENCE"] = "only-managed"
        env["PYTHONUNBUFFERED"] = "1"
        env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        env.removeValue(forKey: "PYTHONPATH"); env.removeValue(forKey: "PYTHONHOME")
        child.environment = env; child.standardOutput = pipe; child.standardError = pipe
        child.standardInput = FileHandle.nullDevice
        process = child
        try child.run()
        try? pipe.fileHandleForWriting.close()
        do {
            for try await line in pipe.fileHandleForReading.bytes.lines {
                details = String((details + line + "\n").suffix(16000))
                // Keep a bounded log after a failed or dismissed installation.
                try? details.write(to: root.appending(path: "install.log"), atomically: true, encoding: .utf8)
            }
        } catch {
            if child.isRunning { child.terminate() }
            await Self.waitForExit(child)
            process = nil
            throw error
        }
        await Self.waitForExit(child)
        process = nil
        try Task.checkCancellation()
        guard child.terminationStatus == 0 else { throw InstallError.message("Installation failed (exit \(child.terminationStatus)). Open Details for the download or package error, then retry.") }
    }
    @concurrent private static func waitForExit(_ child: Process) async {
        child.waitUntilExit()
    }
}
private enum InstallError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { text } else { nil } }
}

struct EngineSetupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var accepted = false
    @State private var showDetails = false
    private var license: String {
        guard let url = Bundle.main.resourceURL?.appending(path: "XTTS-MODEL-LICENSE.txt") else { return "License unavailable. Reinstall VoiceStudio." }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? "License unavailable. Reinstall VoiceStudio."
    }
    var body: some View {
        let installer = model.installer
        VStack(alignment: .leading, spacing: Space.lg) {
            Label("Install Speech Engine", systemImage: "waveform").font(.title2.bold()).gridProbe("setup-title", area: "engine-setup")
            Text("VoiceStudio installs Python, audio tools, and XTTS-v2 for this account. Allow about 8 GB of free space and an internet connection. After setup, speech generation runs locally.")
                .foregroundStyle(.secondary)
            if !installer.completed {
                Text("Coqui Public Model License").font(.headline)
                ScrollView { Text(license).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(Space.sm) }
                    .frame(height: 160).border(.separator)
                Link("Read the model terms online", destination: URL(string: "https://huggingface.co/coqui/XTTS-v2/blob/main/LICENSE.txt")!)
                Toggle("I accept the Coqui Public Model License, including its non-commercial terms.", isOn: $accepted)
                    .disabled(installer.running)
            }
            if installer.running {
                HStack(spacing: Space.md) { ProgressView().controlSize(.small); Text(installer.status) }
                Text("The first download and model check can take several minutes.").font(.caption).foregroundStyle(.secondary)
            } else if installer.completed {
                Label("Speech engine verified and ready to use.", systemImage: "checkmark.circle.fill")
            }
            if !installer.error.isEmpty { Text(installer.error).foregroundStyle(.secondary).textSelection(.enabled) }
            DisclosureGroup("Details", isExpanded: $showDetails) {
                ScrollView { Text(installer.details.isEmpty ? installer.root.path : installer.details).font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 120)
            }
            HStack {
                if installer.running { Button("Cancel Installation") { installer.cancel() } }
                Spacer()
                Button(installer.completed ? "Done" : "Later") { dismiss() }.disabled(installer.running)
                if !installer.completed {
                    Button(installer.error.isEmpty ? "Install Speech Engine" : "Retry Installation") {
                        installer.install(accepted: accepted) { model.adoptInstalledEngine() }
                    }.buttonStyle(.borderedProminent).disabled(!accepted || installer.running || model.queueRunning)
                }
            }
        }.padding(Space.xl).frame(width: 640).fixedSize(horizontal: false, vertical: true).gridArea("engine-setup").noInitialFocus().interactiveDismissDisabled(model.installer.running)
    }
}
